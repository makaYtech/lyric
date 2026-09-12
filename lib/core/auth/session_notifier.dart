import 'package:flutter/foundation.dart';

/// Глобальный сигнал «сессия истекла, нужна переавторизация».
/// Сервисы дёргают markExpired(), HomeScreen слушает и показывает модалку.
/// После успешного re-auth HomeController вызывает clear().
///
/// Синглтон, потому что сервисы создаются по месту и не имеют общего
/// владельца, а сигнал должен быть один на всё приложение.
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

  /// Сброс флага при logout. Семантически отличается от clear() только
  /// тем, откуда зовётся; поведение то же — если флага и не было,
  /// ничего не делаем и никого не будим.
  void reset() {
    if (!_needsAuth) return;
    _needsAuth = false;
    notifyListeners();
  }
}