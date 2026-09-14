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
    if (state != _state) return;

    _authEposCookies = await _readDocumentCookies();
    _code = code;
    _phase = _Phase.eduEpos;
    if (mounted) setState(() => _status = 'Получение сессии ЭПОС...');
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