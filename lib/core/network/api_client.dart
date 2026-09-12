import 'dart:convert';

import '../../services/auth_service.dart';
import '../../services/epos_response_guard.dart';
import '../../services/retry.dart';
import '../../services/session_expired_exception.dart';
import 'epos_http_client.dart';

/// Единая точка ВСЕХ запросов к ЭПОСу.
/// Сервисы (GradesService, ScheduleService, ...) больше не создают
/// http.Client и не собирают заголовки сами — только формируют Uri
/// и зовут get()/getList().
class ApiClient {
  Future<Map<String, dynamic>> get(
      Uri url,
      EposTokens tokens, {
        int attempts = 3,
      }) async {
    final decoded = await _request(url, tokens, attempts: attempts);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }

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
      // Истёкшую сессию не глушим НИКОГДА — иначе SessionNotifier
      // не узнает, что пора показать модалку re-auth. silent относится
      // только к «обычным» сетевым ошибкам (нет связи, 500 и т.п.).
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
      }) {
    return withRetry(() => _once(url, tokens), attempts: attempts);
  }

  Future<dynamic> _once(Uri url, EposTokens tokens) async {
    final client = await createEposHttpClient();
    try {
      final response = await client.get(
        url,
        headers: {
          'Auth-Token': tokens.authToken,
          'Profile-Id': tokens.profileId,
          'Accept': 'application/json',
        },
      );
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