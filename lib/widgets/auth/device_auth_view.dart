import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/auth/device_token_auth.dart';
import '../../core/auth/epos_session.dart';
import '../../core/auth/session_refresh_service.dart';
import '../../core/layout/adaptive.dart';
import './manual_login_dialog.dart';

/// Общий WebView-flow входа по device-token.
///
/// Используется и первым входом ([DeviceLoginScreen]), и перелогином
/// ([DeviceReauthScreen]) — отличается только судьба готовой сессии.
class DeviceAuthView extends StatefulWidget {
  /// Что сделать с готовой сессией: pushReplacement или pop.
  final void Function(BuildContext context, EposSession session) onSession;

  /// Текст ошибки, когда обмен токена не удался.
  final String deadMessage;

  const DeviceAuthView({
    super.key,
    required this.onSession,
    required this.deadMessage,
  });

  @override
  State<DeviceAuthView> createState() => _DeviceAuthViewState();
}

class _DeviceAuthViewState extends State<DeviceAuthView> {
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
    // Платформенного webview нет (desktop, тесты) — оставляем только
    // хоткей ручного token-входа.
    if (!AdaptiveLayout.hasWebView) return;
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

  Future<void> _onTokenFound(String deviceToken) =>
      _enterWithToken(deviceToken);

  /// Обмен device-токена на полную сессию. null — не вышло, статус уже
  /// выставлен. При ручном вводе profileId приходит от пользователя —
  /// без него _doStudentProfile активирует не тот профиль.
  Future<EposSession?> _buildDeviceSession(
    String deviceToken, {
    String? profileId,
  }) async {
    final result = await DeviceTokenAuthService.instance.exchange(
      deviceToken,
      profileId: profileId,
    );
    if (!mounted) return null;

    final payload = result.payload;
    if (payload == null) {
      setState(() {
        _status = result.dead
            ? widget.deadMessage
            : 'Сетевая ошибка: ${result.error ?? "неизвестно"}';
      });
      return null;
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
    if (!mounted) return null;
    return session;
  }

  /// Вход по device-токену: обмен + передача сессии. Годится и для
  /// отловленного deep-link, и для ручного ввода (тогда задан profileId).
  Future<void> _enterWithToken(String deviceToken, {String? profileId}) async {
    if (_busy || _done) return;
    _busy = true;
    if (mounted) setState(() => _status = 'Обмен токена на сессию...');

    final session = await _buildDeviceSession(
      deviceToken,
      profileId: profileId,
    );
    if (!mounted) return;
    if (session == null) {
      _busy = false;
      return;
    }

    _done = true;
    widget.onSession(context, session);
  }

  Future<void> _openManualTokenDialog() async {
    if (_busy || _done) return;
    final creds = await showManualLoginDialog(context);
    if (creds == null || !mounted) return;
    await _enterWithToken(creds.token, profileId: creds.profileId);
  }

  @override
  Widget build(BuildContext context) {
    return _DevBindings(
      onManualToken: _openManualTokenDialog,
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    if (!AdaptiveLayout.hasWebView) {
      return Scaffold(appBar: AppBar(title: const Text('Вход в ЭПОС')));
    }
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

/// Debug-хоткей на экране входа: Ctrl+Shift+D открывает ручной ввод
/// device-токена. Не мешает обычному сценарию, для тестов без Госуслуг.
class _DevBindings extends StatelessWidget {
  final VoidCallback onManualToken;
  final Widget child;

  const _DevBindings({required this.onManualToken, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: true,
        ): onManualToken,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
