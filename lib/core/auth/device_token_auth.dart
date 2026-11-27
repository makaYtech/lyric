import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../network/epos_http_client.dart';
import './auth_config.dart';

const _base = 'https://edu-epos.permkrai.ru';
const _authenticateUrl = '$_base/authenticate';
const _studentProfileUrl = '$_base/authenticate/student_profile';
const _loginEomUrl = '$_base/authenticate/loginEom';
const _deepLinkScheme = 'diaryperm://';
const _deviceKeyStorageKey = 'epos_device_key_v1';
const _ua = 'okhttp/4.12.0';

/// Вход и refresh через долгоживущий device-token.
///
/// Флоу (снято с официального android-клиента):
///   1. WebView → /authenticate/oauth?app=phone&mode=epos&sub_provider=esia.
///   2. Редирект на `diaryperm://redirect?token=<UUID>` — ловим и отменяем.
///   3. GET /authenticate с заголовком `token: <UUID>` — сервер ставит cookies.
///   4. POST /authenticate/student_profile с `{"auth_token": "<UUID>",
///      "profile_id": <id>}` — в body именно UUID, не hex из cookie!
///   5. GET /authenticate/loginEom — финализирует сессию.
///
/// Refresh = повторить шаги 3–5; сам device_token не меняется.
class DeviceTokenAuthService {
  DeviceTokenAuthService._();
  static final instance = DeviceTokenAuthService._();

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 24 случайных байта → 32 base64url-символа. Ключ не критичен для
  /// флоу, оставлен для совместимости с уже сохранёнными сессиями.
  static String _generateDeviceKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<String> ensureDeviceKey() async {
    final saved = await _secureStorage.read(key: _deviceKeyStorageKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final fresh = _generateDeviceKey();
    await _secureStorage.write(key: _deviceKeyStorageKey, value: fresh);
    return fresh;
  }

  Future<String?> readDeviceKey() =>
      _secureStorage.read(key: _deviceKeyStorageKey);

  Future<void> resetDeviceKey() =>
      _secureStorage.delete(key: _deviceKeyStorageKey);

  /// WebView, готовый к интерактивному входу. Зовёт onTokenFound, когда
  /// поймает deep-link. Зовёт onStatus для UI-подписи.
  Future<WebViewController> createLoginController({
    required void Function(String deviceToken) onTokenFound,
    required void Function(String status) onStatus,
  }) async {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            if (req.url.startsWith(_deepLinkScheme)) {
              final uri = Uri.tryParse(req.url);
              final token = uri?.queryParameters['token'];
              if (token != null && token.isNotEmpty) {
                onTokenFound(token);
              } else {
                onStatus('deep-link без token');
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: onStatus,
          onWebResourceError: (e) {
            if (e.isForMainFrame == false) return;
            onStatus('Ошибка загрузки: ${e.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('$_base${AuthConfig.deviceLoginStartPath}'));
    return controller;
  }

  /// Полный обмен: GET /authenticate → POST student_profile → GET loginEom.
  /// Возвращает ВСЕ cookies за три запроса.
  ///
  /// [profileId] — для ручного ввода токена: cookie сервера может быть
  /// пустой или чужой, а шаг student_profile активирует именно профиль.
  Future<DeviceExchangeResult> exchange(
    String deviceToken, {
    String? profileId,
  }) async {
    final client = await createEposRawHttpClient();
    try {
      final step1 = await _doAuthenticate(client, deviceToken);
      if (step1.dead) return const DeviceExchangeResult.authDead();
      final cookies = step1.cookies;
      if (cookies == null || cookies.isEmpty) {
        return const DeviceExchangeResult.network('authenticate: пусто');
      }
      final resolved = (profileId != null && profileId.isNotEmpty)
          ? profileId
          : cookies['profile_id'];
      if (resolved == null || resolved.isEmpty) {
        return const DeviceExchangeResult.authDead();
      }
      cookies['profile_id'] = resolved;

      await _doStudentProfile(
        client,
        cookies: cookies,
        deviceToken: deviceToken,
        profileId: resolved,
      );

      await _doLoginEom(client, cookies: cookies, profileId: resolved);

      return DeviceExchangeResult.success(
        DeviceExchangePayload(cookies: cookies, profileId: resolved),
      );
    } catch (e) {
      return DeviceExchangeResult.network('$e');
    } finally {
      client.close(force: true);
    }
  }

  /// Шаг 1. dead — 401/403 (токен мёртв); cookies == null — сеть/сервер,
  /// токен скорее всего жив.
  Future<({Map<String, String>? cookies, bool dead})> _doAuthenticate(
    HttpClient client,
    String deviceToken,
  ) async {
    final req = await client.getUrl(Uri.parse(_authenticateUrl));
    req.headers.set('token', deviceToken);
    req.headers.set('User-Agent', _ua);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    await resp.drain<void>();

    if (resp.statusCode == 200) {
      return (cookies: _collectCookies(resp.headers), dead: false);
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return (cookies: null, dead: true);
    }
    throw Exception('authenticate: HTTP ${resp.statusCode}');
  }

  /// Шаг 2: в body auth_token — UUID из deep-link, не cookie. Не-200
  /// не критичен: эндпоинт активирует профиль и дописывает waf_cookie.
  Future<void> _doStudentProfile(
    HttpClient client, {
    required Map<String, String> cookies,
    required String deviceToken,
    required String profileId,
  }) async {
    final req = await client.postUrl(Uri.parse(_studentProfileUrl));
    req.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    req.headers.set('User-Agent', _ua);
    req.write(
      jsonEncode({
        'auth_token': deviceToken,
        'profile_id': int.tryParse(profileId) ?? profileId,
      }),
    );
    final resp = await req.close().timeout(const Duration(seconds: 20));
    await resp.drain<void>();
    _mergeCookies(cookies, resp.headers);
  }

  /// Шаг 3: финализирует логин, обновляет waf_cookie и SERVERID.
  Future<void> _doLoginEom(
    HttpClient client, {
    required Map<String, String> cookies,
    required String profileId,
  }) async {
    final req = await client.getUrl(Uri.parse(_loginEomUrl));
    req.headers.set('auth-token', '');
    req.headers.set('profile-id', profileId);
    req.headers.set('Cookie', _buildCookieHeader(cookies));
    req.headers.set('User-Agent', _ua);
    final resp = await req.close().timeout(const Duration(seconds: 20));
    await resp.drain<void>();
    _mergeCookies(cookies, resp.headers);
  }

  static String _buildCookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Извлекает name=value из всех Set-Cookie в ответе.
  static Map<String, String> _collectCookies(HttpHeaders headers) {
    final out = <String, String>{};
    _mergeCookies(out, headers);
    return out;
  }

  /// Дописывает Set-Cookie из headers в существующую мапу.
  /// Несколько Set-Cookie приходят разными значениями одного заголовка —
  /// HttpHeaders.forEach даёт их списком.
  static void _mergeCookies(Map<String, String> target, HttpHeaders headers) {
    headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') return;
      for (final raw in values) {
        final eq = raw.indexOf('=');
        if (eq <= 0) continue;
        final key = raw.substring(0, eq).trim();
        final val = raw.substring(eq + 1).split(';').first.trim();
        if (key.isNotEmpty) target[key] = val;
      }
    });
  }
}

class DeviceExchangePayload {
  /// Все cookies, которые нужно вернуть в последующих запросах.
  final Map<String, String> cookies;
  final String profileId;

  const DeviceExchangePayload({required this.cookies, required this.profileId});
}

/// Результат обмена device-token.
/// - payload != null — успех, сессию можно обновлять.
/// - dead == true     — токен мёртв, нужен интерактивный вход.
/// - error != null    — сеть/сервер, повторить позже.
class DeviceExchangeResult {
  final DeviceExchangePayload? payload;
  final bool dead;
  final String? error;

  const DeviceExchangeResult._({this.payload, this.dead = false, this.error});
  const DeviceExchangeResult.success(DeviceExchangePayload p)
    : this._(payload: p);
  const DeviceExchangeResult.authDead() : this._(dead: true);
  const DeviceExchangeResult.network(String e) : this._(error: e);
}
