import 'dart:async';

import 'session_expired_exception.dart';

/// Повторяет [action] до [attempts] раз с экспоненциальной задержкой.
/// Полезно для нестабильного API — если упадёт 1-2 раза, дойдёт с 3-го.
///
/// SessionExpiredException не ретраится: повторные запросы с мёртвой
/// сессией бессмысленны, а сервер это только раздражает. Пусть долетает
/// сразу до SessionNotifier — тот покажет модалку re-auth.
Future<T> withRetry<T>(
    Future<T> Function() action, {
      int attempts = 5,
      Duration initialDelay = const Duration(milliseconds: 400),
      void Function(int attempt, Object error)? onError,
    }) async {
  Object? lastError;
  for (var i = 1; i <= attempts; i++) {
    try {
      return await action();
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      lastError = e;
      onError?.call(i, e);
      if (i < attempts) {
        final delay = initialDelay * (1 << (i - 1)); // 400, 800, 1600, ...
        await Future.delayed(delay);
      }
    }
  }
  throw lastError ?? Exception('withRetry: no attempts');
}