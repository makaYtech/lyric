import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/epos_oauth_client.dart';
import '../core/auth/epos_session.dart';
import '../core/auth/session_refresh_service.dart';

class ReauthScreen extends StatefulWidget {
  const ReauthScreen({super.key});

  @override
  State<ReauthScreen> createState() => _ReauthScreenState();
}

enum _Phase { pkce, eduEpos, done }

const _stepTimeout = Duration(seconds: 15);

class _ReauthScreenState extends State<ReauthScreen> {
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

  Timer? _timeoutTimer;
  bool _failed = false;

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
        onWebResourceError: _onWebResourceError,
      ))
      ..loadRequest(
        _oauth.buildAuthUrl(challenge: _challenge, state: _state),
      );
    _armTimeout();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  /// Перезапускается при каждом реальном прогрессе. Если за
  /// _stepTimeout ничего не произошло — вероятно, нет сети, и WebView
  /// просто молча висит без единого колбэка.
  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_stepTimeout, () {
      if (_busy || _failed) return;
      _fail('Не удалось загрузить страницу входа. Проверьте подключение к интернету.');
    });
  }

  void _onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    if (_busy || _failed) return;
    _fail('Ошибка загрузки: ${error.description}');
  }

  void _fail(String message) {
    _timeoutTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _failed = true;
      _status = message;
    });
  }

  Future<void> _onPageFinished(String url) async {
    if (_busy || _failed) return;
    if (mounted) setState(() => _status = url);
    _armTimeout();
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
    if (state != _state) return;

    _authEposCookies = await _readDocumentCookies();
    _code = code;
    _phase = _Phase.eduEpos;
    if (mounted) setState(() => _status = 'Получение сессии ЭПОС...');
    _armTimeout();
    await _controller.loadRequest(Uri.parse(
      'https://edu-epos.permkrai.ru/authenticate/oauth'
          '?mode=epos&groupRole=student',
    ));
  }

  Future<void> _handleEduPhase(String url) async {
    if (!url.contains('edu-epos.permkrai.ru')) return;
    if (url.contains('/authenticate/')) return;

    final cookies = await _readDocumentCookies();
    final authToken = cookies['auth_token'];
    final profileId = cookies['profile_id'];
    if (authToken == null || profileId == null) return;

    _phase = _Phase.done;
    _busy = true;
    _timeoutTimer?.cancel();
    if (mounted) setState(() => _status = 'Сохранение...');
    try {
      final EposSession session = await _refreshService.buildAndSave(
        code: _code!,
        verifier: _verifier,
        authEposCookies: _authEposCookies,
        authToken: authToken,
        profileId: profileId,
        longToken: cookies['long_token'],
        userId: int.tryParse(cookies['user_id'] ?? ''),
      );
      if (!mounted) return;
      Navigator.of(context).pop(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Ошибка: $e';
        _busy = false;
        _phase = _Phase.eduEpos;
      });
      _armTimeout();
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
      body: _failed ? _buildFailure(context) : _buildWebView(),
    );
  }

  Widget _buildWebView() {
    return Column(
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
    );
  }

  /// Сеть отвалилась / таймаут — закрываем шторку с null. HomeScreen
  /// сам покажет снэкбар и оставит пользователя с уже загруженными
  /// (из SQLite/SharedPreferences) данными. Повторный заход — снова
  /// через обычную кнопку обновления, а не отдельную кнопку тут.
  Widget _buildFailure(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'Продолжай работать с уже загруженными данными — повторить '
                  'вход можно кнопкой обновления.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }
}