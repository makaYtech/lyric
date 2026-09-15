import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/auth_service.dart';
import 'epos_oauth_client.dart';
import 'epos_session.dart';
import 'session_notifier.dart';
import 'session_refresh_service.dart';

enum RenewOutcome {
  /// Токены обновлены, запрос можно повторять.
  success,

  /// Офлайн-ключ реально мёртв (invalid_grant), либо Keycloak явно
  /// потребовал интерактивный вход, пока страница грузилась. Нужен
  /// живой человек — показываем ReauthScreen.
  authDead,

  /// Не удалось понять, жив ли ключ, из-за сетевой проблемы: таймаут,
  /// обрыв связи, DNS, 5xx, WebView вообще ничего не загрузил. Офлайн-
  /// ключ мог быть абсолютно живым — просто сервер сейчас недоступен.
  /// НЕ повод требовать повторный вход, это обычная ошибка сети.
  networkError,
}

/// Единственный владелец живой сессии и единственная точка её обновления.
///
/// Цепочка обновления ровно та, что проверена curl'ом руками:
///   1. POST /token, grant_type=refresh_token с офлайн-ключом (чистый Dart).
///   2. Сразу WebView на edu-epos/authenticate/oauth — Phase C.
///
/// renew() дедуплицирован: сколько бы запросов одновременно ни поймали
/// 401, реальное обновление выполнится один раз, остальные подождут его.
class AuthCoordinator {
  AuthCoordinator._();
  static final instance = AuthCoordinator._();

  static const _phaseCUrl =
      'https://edu-epos.permkrai.ru/authenticate/oauth?mode=epos&groupRole=student';

  final _oauth = EposOAuthClient();
  final _storage = SessionRefreshService.instance;

  EposSession? _session;
  EposSession? get session => _session;
  EposTokens? get tokens => _session?.tokens;

  WebViewController? _webView;

  Future<RenewOutcome>? _inFlight;
  Completer<RenewOutcome>? _phaseC;
  Timer? _timeout;
  TokenSet? _pendingTokens;
  bool _sawAnyPageLoad = false;

  void setSession(EposSession session) {
    _session = session;
  }

  void attachWebView(WebViewController controller) {
    _webView = controller;
  }

  void detachWebView(WebViewController controller) {
    if (identical(_webView, controller)) _webView = null;
  }

  Future<RenewOutcome> renew() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final fut = _renew().whenComplete(() => _inFlight = null);
    _inFlight = fut;
    return fut;
  }

  Future<RenewOutcome> _renew() async {
    final current = _session;
    if (current == null) return RenewOutcome.networkError;

    // ── Шаг 1: офлайн-ключ, чистый REST ──────────────────────────────
    final TokenSet tokens;
    try {
      tokens = await _oauth
          .refresh(current.refreshToken)
          .timeout(const Duration(seconds: 20));
    } on EposOAuthAuthDeadException {
      return RenewOutcome.authDead;
    } catch (_) {
      return RenewOutcome.networkError;
    }

    // Свежую пару сохраняем сразу — даже если Phase C не дойдёт.
    final withTokens = current.copyWith(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
    );
    _session = withTokens;
    await _storage.save(withTokens);

    // ── Шаг 2: Phase C в скрытом WebView ──────────────────────────────
    final webView = await _waitForWebView();
    if (webView == null) {
      // WebView ещё не смонтирован (гонка при самом старте приложения) —
      // техническая заминка, не «ключ мёртв».
      return RenewOutcome.networkError;
    }

    final completer = Completer<RenewOutcome>();
    _phaseC = completer;
    _pendingTokens = tokens;
    _sawAnyPageLoad = false;
    _timeout = Timer(const Duration(seconds: 20), () {
      // Ни одной загрузки за весь таймаут → страница физически не
      // грузится → дело в сети. Хоть одна загрузка была, но до успеха
      // не дошли → цепочка не смогла завершиться молча → нужен вход.
      _finishPhaseC(
        _sawAnyPageLoad ? RenewOutcome.authDead : RenewOutcome.networkError,
      );
    });

    try {
      await webView.loadRequest(Uri.parse(_phaseCUrl));
    } catch (_) {
      _finishPhaseC(RenewOutcome.networkError);
    }
    return completer.future;
  }

  Future<WebViewController?> _waitForWebView() async {
    for (var i = 0; i < 20; i++) {
      final w = _webView;
      if (w != null) return w;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> onPageFinished(String url) async {
    final completer = _phaseC;
    final webView = _webView;
    final tokens = _pendingTokens;
    if (completer == null || completer.isCompleted) return;
    _sawAnyPageLoad = true;
    if (webView == null || tokens == null) return;

    if (!url.contains('edu-epos.permkrai.ru')) return;
    if (url.contains('/authenticate/')) return;

    final cookies = await _readCookies(webView);
    final authToken = cookies['auth_token'];
    final profileId = cookies['profile_id'];
    if (authToken == null || profileId == null) return;

    final base = _session;
    if (base == null) {
      _finishPhaseC(RenewOutcome.networkError);
      return;
    }

    final updated = EposSession(
      authToken: authToken,
      profileId: profileId,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      longToken: cookies['long_token'] ?? base.longToken,
      userId: int.tryParse(cookies['user_id'] ?? '') ?? base.userId,
    );

    _session = updated;
    await _storage.save(updated);
    SessionNotifier.instance.clear();
    _finishPhaseC(RenewOutcome.success);
  }

  /// Явная сетевая ошибка на главном фрейме (нет интернета, DNS и т.п.) —
  /// не ждём таймаут, сразу считаем это сетевой проблемой.
  void onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    final completer = _phaseC;
    if (completer == null || completer.isCompleted) return;
    _finishPhaseC(RenewOutcome.networkError);
  }

  Future<Map<String, String>> _readCookies(WebViewController webView) async {
    try {
      final raw =
      await webView.runJavaScriptReturningResult('document.cookie');
      final str = raw.toString().replaceAll(RegExp(r'^"|"$'), '');
      final out = <String, String>{};
      for (final pair in str.split('; ')) {
        final i = pair.indexOf('=');
        if (i > 0) out[pair.substring(0, i)] = pair.substring(i + 1);
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  void _finishPhaseC(RenewOutcome result) {
    _timeout?.cancel();
    _timeout = null;
    _pendingTokens = null;
    final completer = _phaseC;
    _phaseC = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }
}

/// Невидимый WebView, постоянно висящий в дереве HomeScreen.
class AuthWebViewHost extends StatefulWidget {
  const AuthWebViewHost({super.key});

  @override
  State<AuthWebViewHost> createState() => _AuthWebViewHostState();
}

class _AuthWebViewHostState extends State<AuthWebViewHost> {
  late final WebViewController _webView;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: AuthCoordinator.instance.onPageFinished,
          onWebResourceError: AuthCoordinator.instance.onWebResourceError,
        ),
      );
    AuthCoordinator.instance.attachWebView(_webView);
  }

  @override
  void dispose() {
    AuthCoordinator.instance.detachWebView(_webView);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0,
          child: IgnorePointer(child: WebViewWidget(controller: _webView)),
        ),
      ),
    );
  }
}