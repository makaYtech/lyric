import 'dart:convert';

import '../../services/auth_service.dart';
import '../../services/epos_response_guard.dart';
import '../../services/retry.dart';
import '../../services/session_expired_exception.dart';
import '../auth/auth_coordinator.dart';
import '../auth/session_notifier.dart';
import 'epos_http_client.dart';

/// Единая точка ВСЕХ запросов к ЭПОСу.
///
/// Основной механизм аутентификации — cookies (aid, auth_token,
/// long_token, profile_id, is_auth, from_sudir, RSESSION, waf_cookie,
/// SERVERID). Заголовки Auth-Token/Profile-Id — fallback для
/// legacy-сессий, где cookies ещё не собраны.
///
/// Реакция на 401/«сессия истекла»: просим AuthCoordinator обновиться
/// и повторяем запрос. Если он ответил networkError — это НЕ повод
/// требовать вход заново, просто всплывает обычная ошибка обновления.
class ApiClient {
  static const _requestTimeout = Duration(seconds: 25);
  static const _userAgent = 'okhttp/4.12.0';

  Future<Map<String, dynamic>> get(
    Uri url,
    EposTokens tokens, {
    int attempts = 3,
  }) async {
    final decoded = await _request(url, tokens, attempts: attempts);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  /// Ответ может быть и List, и Map — разбирается вызывающей стороной.
  Future<dynamic> getRaw(Uri url, EposTokens tokens, {int attempts = 3}) =>
      _request(url, tokens, attempts: attempts);

  Future<List<dynamic>> getList(
    Uri url,
    EposTokens tokens, {
    int attempts = 3,
    bool silent = false,
  }) async {
    try {
      final decoded = await _request(url, tokens, attempts: attempts);
      return decoded is List<dynamic> ? decoded : const [];
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      if (silent) return const [];
      rethrow;
    }
  }

  Future<dynamic> _request(
    Uri url,
    EposTokens tokens, {
    required int attempts,
  }) async {
    try {
      return await withRetry(() => _once(url, tokens), attempts: attempts);
    } on SessionExpiredException {
      final outcome = await AuthCoordinator.instance.renew();
      switch (outcome) {
        case RenewOutcome.success:
          final fresh = AuthCoordinator.instance.tokens ?? tokens;
          try {
            return await withRetry(() => _once(url, fresh), attempts: 1);
          } on SessionExpiredException {
            // Даже со свежими cookies сервер снова говорит «сессия
            // истекла» — это уже не сеть, реально нужен живой вход.
            SessionNotifier.instance.markExpired();
            rethrow;
          }
        case RenewOutcome.authDead:
          SessionNotifier.instance.markExpired();
          rethrow;
        case RenewOutcome.networkError:
          throw Exception('Нет соединения — не удалось обновить сессию');
      }
    }
  }

  Future<dynamic> _once(Uri url, EposTokens tokens) async {
    final client = await createEposHttpClient();
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      };
      if (tokens.cookieHeader.isNotEmpty) {
        headers['Cookie'] = tokens.cookieHeader;
      } else {
        // Legacy-сессия без cookie-jar — старый header-путь.
        headers['Auth-Token'] = tokens.authToken;
        headers['Profile-Id'] = tokens.profileId;
      }

      final response = await client
          .get(url, headers: headers)
          .timeout(_requestTimeout);
      ensureSessionValid(response);
      if (response.statusCode != 200) {
        final body = utf8.decode(response.bodyBytes, allowMalformed: true);
        final snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
        throw Exception('${url.path} вернул ${response.statusCode}: $snippet');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } finally {
      client.close();
    }
  }
}
