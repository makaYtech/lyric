import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/device_token_auth.dart';
import '../core/auth/epos_session.dart';
import '../core/auth/session_refresh_service.dart';
import '../core/theme/theme_controller.dart';
import 'home_screen.dart';

/// Интерактивный вход по новому flow: ESIA-логин через WebView,
/// ловля diaryperm://redirect?token=, трёхшаговый exchange на cookie-сессию
/// (см. DeviceTokenAuthService.exchange).
///
/// В конце НЕ возвращает значение — pushReplacement'ит HomeScreen.
/// Для случая "перелогин из HomeScreen" есть DeviceReauthScreen.
class DeviceLoginScreen extends StatefulWidget {
  final ThemeController themeController;
  const DeviceLoginScreen({super.key, required this.themeController});

  @override
  State<DeviceLoginScreen> createState() => _DeviceLoginScreenState();
}

class _DeviceLoginScreenState extends State<DeviceLoginScreen> {
  WebViewController? _controller;
  String _status = 'Загрузка...';
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = await DeviceTokenAuthService.instance.createLoginController(
        onStatus: (s) {
          if (mounted && !_done) setState(() => _status = s);
        },
        onTokenFound: _onTokenFound,
      );
      if (!mounted) return;
      setState(() => _controller = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка запуска WebView: $e');
    }
  }

  Future<void> _onTokenFound(String deviceToken) async {
    if (_busy || _done) return;
    _busy = true;
    if (mounted) setState(() => _status = 'Обмен токена на сессию...');

    final result = await DeviceTokenAuthService.instance.exchange(deviceToken);
    if (!mounted) return;

    final payload = result.payload;
    if (payload == null) {
      setState(() {
        _status = result.dead
            ? 'Не удалось получить сессию. Попробуйте войти заново.'
            : 'Сетевая ошибка: ${result.error ?? "неизвестно"}';
        _busy = false;
      });
      return;
    }

    final session = EposSession(
      // authToken в EposSession — это UUID из deep-link. Он же
      // используется в POST /authenticate/student_profile.
      authToken: deviceToken,
      profileId: payload.profileId,
      deviceToken: deviceToken,
      cookies: payload.cookies,
      longToken: payload.cookies['long_token'],
      userId: int.tryParse(payload.cookies['user_id'] ?? ''),
    );
    await SessionRefreshService.instance.save(session);
    if (!mounted) return;

    _done = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          session: session,
          themeController: widget.themeController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в ЭПОС')),
      body: Column(
        children: [
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
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
