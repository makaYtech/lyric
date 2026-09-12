/// Бросается, когда сервер ЭПОСа отвечает признаком истёкшей сессии:
/// либо голым 401/403, либо телом {"message":"Войдите в ЭЖД заново"}.
class SessionExpiredException implements Exception {
  const SessionExpiredException();

  @override
  String toString() => 'Сессия ЭПОСа истекла';
}