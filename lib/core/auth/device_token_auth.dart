import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../network/epos_http_client.dart';
import 'auth_config.dart';

const _base = 'https://edu-epos.permkrai.ru';
const _exchangeUrl = '$_base/authenticate';
const _deepLinkScheme = 'diaryperm://';
const _deviceKeyStorageKey = 'epos_device_key_v1';

/// Вход и refresh через долгоживущий device-token.
///
/// Схема (снято с официального android-клиента ru.permkrai.school):
///   1. WebView → /authenticate/oauth?app=phone&mode=epos&sub_provider=esia
///      &device_key=<random>. Пользователь проходит ESIA (логин/пароль/TOTP).
///   2. Цепочка редиректов заканчивается на diaryperm://redirect?token=<UUID>.
///      Ловим его в onNavigationRequest, отменяем навигацию.
///   3. GET /authenticate с заголовком `token: <UUID>` → 200 +
///      Set-Cookie: auth_token=<hex32>; profile_id=<int>; long_token=<uuid>.
///   4. Дальше работаем тем же cookie-значением auth_token/profile_id,
///      что и раньше — ApiClient кладёт их в заголовки Auth-Token/Profile-Id.
///
/// Refresh = повторить шаг 3. Один HTTP-запрос, никакого WebView.
class DeviceTokenAuthService {
  DeviceTokenAuthService._();
  static final instance = DeviceTokenAuthService._();

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// 24 случайных байта → 32 base64url-символа. Формат device_key из
  /// дампа (там он совпадает с префиксом FCM-токена). Серверу он нужен
  /// просто как стабильный идентификатор клиента в рамках логина.
  static String _generateDeviceKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(24, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Один device_key на установку приложения. Первый вызов генерирует
  /// и сохраняет, последующие — только читают. Ключ переживает logout
  /// и перезапуск: он не часть сессии, а стабильный идентификатор клиента.
  Future<String> ensureDeviceKey() async {
    final saved = await _secureStorage.read(key: _deviceKeyStorageKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final fresh = _generateDeviceKey();
    await _secureStorage.write(key: _deviceKeyStorageKey, value: fresh);
    return fresh;
  }

  /// Текущий ключ (если уже сгенерирован). Для девелоперского экрана.
  Future<String?> readDeviceKey() =>
      _secureStorage.read(key: _deviceKeyStorageKey);

  /// Сбросить ключ. Следующий логин сгенерирует новый.
  /// Старый ключ на сервере остаётся — сам по себе он бесполезен.
  Future<void> resetDeviceKey() =>
      _secureStorage.delete(key: _deviceKeyStorageKey);

  /// WebView, готовый к интерактивному входу. Зовёт onTokenFound, когда
  /// поймает deep-link. Зовёт onStatus для UI-подписи.
  Future<WebViewController> createLoginController({
    required void Function(String deviceToken) onTokenFound,
    required void Function(String status) onStatus,
  }) async {
    final deviceKey = await ensureDeviceKey();
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
      ..loadRequest(
        Uri.parse('$_base${AuthConfig.deviceLoginStartPath}$deviceKey'),
      );
    return controller;
  }

  /// Обмен device-token на свежие cookie-значения.
  /// Используется и при первичном логине, и при refresh (см. AuthCoordinator).
  Future<DeviceExchangeResult> exchange(String deviceToken) async {
    final client = await createEposRawHttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_exchangeUrl));
      req.headers.set('token', deviceToken);
      req.headers.set('User-Agent', 'okhttp/4.12.0');
      final resp = await req.close().timeout(const Duration(seconds: 20));
      await resp.drain<void>();

      if (resp.statusCode != 200) {
        // 4xx — токен реально мёртв (отозван / просрочен).
        // 5xx — сервер лежит, токен скорее всего жив.
        if (resp.statusCode >= 400 && resp.statusCode < 500) {
          return const DeviceExchangeResult.authDead();
        }
        return DeviceExchangeResult.network('HTTP ${resp.statusCode}');
      }

      final cookies = _collectCookies(resp.headers);
      final authToken = cookies['auth_token'];
      final profileId = cookies['profile_id'];
      if (authToken == null || profileId == null) {
        return const DeviceExchangeResult.authDead();
      }

      return DeviceExchangeResult.success(DeviceExchangePayload(
        authToken: authToken,
        profileId: profileId,
        longToken: cookies['long_token'],
        aid: cookies['aid'],
      ));
    } catch (e) {
      return DeviceExchangeResult.network('$e');
    } finally {
      client.close(force: true);
    }
  }

  /// Проходим по всем Set-Cookie и собираем пары name=value. Path/expires
  /// отрезаем. Несколько Set-Cookie приходят разными значениями одного
  /// заголовка — HttpHeaders.forEach даёт их списком.
  static Map<String, String> _collectCookies(HttpHeaders headers) {
    final out = <String, String>{};
    headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') return;
      for (final raw in values) {
        final eq = raw.indexOf('=');
        if (eq <= 0) continue;
        final key = raw.substring(0, eq).trim();
        final val = raw.substring(eq + 1).split(';').first.trim();
        if (key.isNotEmpty) out[key] = val;
      }
    });
    return out;
  }
}

class DeviceExchangePayload {
  final String authToken;
  final String profileId;
  final String? longToken;
  final String? aid;

  const DeviceExchangePayload({
    required this.authToken,
    required this.profileId,
    this.longToken,
    this.aid,
  });
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