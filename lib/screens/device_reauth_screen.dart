import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/device_token_auth.dart';
import '../core/auth/epos_session.dart';
import '../core/auth/session_refresh_service.dart';

/// Тот же новый flow, что и DeviceLoginScreen, но для случая
/// "перелогин из HomeScreen": возвращает EposSession через pop.
class DeviceReauthScreen extends StatefulWidget {
  const DeviceReauthScreen({super.key});

  @override
  State<DeviceReauthScreen> createState() => _DeviceReauthScreenState();
}

class _DeviceReauthScreenState extends State<DeviceReauthScreen> {
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
            ? 'Не удалось получить сессию. Попробуйте ещё раз.'
            : 'Сетевая ошибка: ${result.error ?? "неизвестно"}';
        _busy = false;
      });
      return;
    }

    final session = EposSession(
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
    Navigator.of(context).pop(session);
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
