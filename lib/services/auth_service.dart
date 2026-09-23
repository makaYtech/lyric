/// Токены для запросов к API ЭПОСа. Используются во всех
/// репозиториях и ApiClient. Живут «внутри» EposSession.
///
/// Основной механизм аутентификации в оригинальном приложении —
/// cookies (см. дампы сетевого трафика): aid, auth_token, long_token,
/// profile_id, is_auth, from_sudir, RSESSION, waf_cookie, SERVERID.
/// Заголовки Auth-Token / Profile-Id оставлены как fallback для
/// legacy-сессий, где cookie-jar ещё не собран.
class EposTokens {
  final String authToken;
  final String profileId;

  /// Готовый Cookie-заголовок: "aid=14; auth_token=...; profile_id=...".
  /// Если пусто — ApiClient использует заголовки Auth-Token/Profile-Id.
  final String cookieHeader;

  EposTokens({
    required this.authToken,
    required this.profileId,
    this.cookieHeader = '',
  });
}
