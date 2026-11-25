import 'package:flutter/foundation.dart';

/// Глобальный сигнал «сессия истекла, нужна переавторизация».
/// Сервисы дёргают markExpired(), HomeScreen слушает и показывает модалку.
class SessionNotifier extends ChangeNotifier {
  SessionNotifier._();
  static final SessionNotifier instance = SessionNotifier._();

  bool _needsAuth = false;
  bool get needsAuth => _needsAuth;

  void markExpired() {
    if (_needsAuth) return;
    _needsAuth = true;
    notifyListeners();
  }

  void clear() {
    if (!_needsAuth) return;
    _needsAuth = false;
    notifyListeners();
  }

  /// Сброс флага при logout; поведение то же, что у clear().
  void reset() {
    if (!_needsAuth) return;
    _needsAuth = false;
    notifyListeners();
  }
}
