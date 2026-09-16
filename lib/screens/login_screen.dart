import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/auth_config.dart';
import '../core/auth/epos_oauth_client.dart';
import '../core/auth/session_refresh_service.dart';
import '../core/backend/backends.dart';
import '../core/backend/backends_prefs.dart';
import '../core/theme/theme_controller.dart';
import 'device_login_screen.dart';
import 'home_screen.dart';
import 'myschool_login_screen.dart';

/// Диспатчер входа: по бэкенду → по AuthConfig.useDeviceTokenFlow.
/// Сам login здесь только выбирает экран — вся реальная работа либо в
/// DeviceLoginScreen (новый flow), либо в _EposLoginView (legacy).
///
/// ValueListenableBuilder нужен потому, что флаг теперь меняется в
/// рантайме из DeveloperScreen. Если пользователь переключит flow и
/// окажется на этом экране — LoginScreen сам перерисуется на нужный.
class LoginScreen extends StatelessWidget {
  final ThemeController themeController;

  const LoginScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: BackendPrefs.current,
      builder: (context, backend, _) {
        if (backend == Backends.mySchool) {
          return MySchoolLoginScreen(themeController: themeController);
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AuthConfig.useDeviceTokenFlow,
          builder: (context, useDevice, _) {
            if (useDevice) {
              return DeviceLoginScreen(themeController: themeController);
            }
            return _EposLoginView(themeController: themeController);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// LEGACY PKCE flow. Не используется при useDeviceTokenFlow == true,
// но оставлен живым: если новый flow вдруг окажется нерабочим в каком-то
// сценарии, достаточно переключить флаг в DeveloperScreen — и код снова
// заработает без отката.
// ─────────────────────────────────────────────────────────────────────────

class _EposLoginView extends StatefulWidget {
  final ThemeController themeController;
  const _EposLoginView({required this.themeController});

  @override
  State<_EposLoginView> createState() => _EposLoginViewState();
}

enum _Phase { pkce, eduEpos, done }

class _EposLoginViewState extends State<_EposLoginView> {
  final _oauth = EposOAuthClient();
  final _refreshService = SessionRefreshService.instance;

  late final String _verifier;
  late final String _challenge;
  late final String _state;
  late final WebViewController _controller;

  _Phase _phase = _Phase.pkce;
  String _status = 'Загрузка...';
  bool _busy = false;
  String? _code;
  Map<String, String> _authEposCookies = {};

  @override
  void initState() {
    super.initState();
    _verifier = EposOAuthClient.generateVerifier();
    _challenge = EposOAuthClient.challengeFor(_verifier);
    _state = EposOAuthClient.generateState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _onPageFinished,
      ))
      ..loadRequest(
        _oauth.buildAuthUrl(challenge: _challenge, state: _state),
      );
  }

  Future<void> _onPageFinished(String url) async {
    if (_busy) return;
    if (mounted) setState(() => _status = url);

    if (_phase == _Phase.pkce) {
      await _handlePkcePhase(url);
    } else if (_phase == _Phase.eduEpos) {
      await _handleEduPhase(url);
    }
  }

  Future<void> _handlePkcePhase(String url) async {
    if (!url.contains('auth-epos.permkrai.ru')) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.fragment.isEmpty) return;
    final params = Uri.splitQueryString(uri.fragment);
    final code = params['code'];
    final state = params['state'];
    if (code == null || state == null) return;
    if (state != _state) {
      if (mounted) setState(() => _status = 'Ошибка: state не совпал');
      return;
    }

    // Сохраняем куки auth-epos — понадобятся для exchange.
    // document.cookie не видит HttpOnly, но для /token-запроса
    // Keycloak принимает заголовки как основной канал.
    _authEposCookies = await _readDocumentCookies();
    _code = code;

    // Фаза 2: грузим edu-epos-flow в тот же WebView.
    // Keycloak-сессия в WebView уже установлена — редирект произойдёт
    // молча, без Госуслуг.
    _phase = _Phase.eduEpos;
    if (mounted) setState(() => _status = 'Получение сессии ЭПОС...');
    await _controller.loadRequest(Uri.parse(
      'https://edu-epos.permkrai.ru/authenticate/oauth'
          '?mode=epos&groupRole=student',
    ));
  }

  Future<void> _handleEduPhase(String url) async {
    // Ждём, пока WebView окажется на edu-epos (не на /authenticate).
    if (!url.contains('edu-epos.permkrai.ru')) return;
    if (url.contains('/authenticate/')) return;

    final cookies = await _readDocumentCookies();
    final authToken = cookies['auth_token'];
    final profileId = cookies['profile_id'];
    final longToken = cookies['long_token'];
    final userId = int.tryParse(cookies['user_id'] ?? '');

    if (authToken == null || profileId == null) {
      // Ещё не всё выставилось, попробуем на следующем onPageFinished.
      return;
    }

    _phase = _Phase.done;
    _busy = true;
    if (mounted) setState(() => _status = 'Сохранение сессии...');

    try {
      final session = await _refreshService.buildAndSave(
        code: _code!,
        verifier: _verifier,
        authEposCookies: _authEposCookies,
        authToken: authToken,
        profileId: profileId,
        longToken: longToken,
        userId: userId,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            session: session,
            themeController: widget.themeController,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка: $e';
        _busy = false;
        _phase = _Phase.eduEpos;
      });
    }
  }

  Future<Map<String, String>> _readDocumentCookies() async {
    try {
      final raw = await _controller
          .runJavaScriptReturningResult('document.cookie');
      final str = raw.toString().replaceAll(RegExp(r'^"|"$'), '');
      final out = <String, String>{};
      for (final pair in str.split('; ')) {
        final i = pair.indexOf('=');
        if (i > 0) out[pair.substring(0, i)] = pair.substring(i + 1);
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в ЭПОС')),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _status,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}