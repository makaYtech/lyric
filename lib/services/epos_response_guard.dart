import 'package:http/http.dart' as http;

import 'session_expired_exception.dart';

/// Проверяет ответ ЭПОСа на признаки того, что сессия истекла.
/// Бросает SessionExpiredException, иначе молчит.
/// Вызывать сразу после каждого http-запроса, до разбора содержимого.
void ensureSessionValid(http.Response resp) {
  if (resp.statusCode == 401 || resp.statusCode == 403) {
    throw const SessionExpiredException();
  }
  // Некоторые ручки отвечают 200 с сообщением об истёкшей сессии.
  // Проверяем только по точной фразе, чтобы не спутать с осмысленным
  // контентом (текст ДЗ, название темы и т.п.).
  if (resp.body.contains('Войдите в ЭЖД заново')) {
    throw const SessionExpiredException();
  }
}