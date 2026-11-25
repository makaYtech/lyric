/// Токены для запросов к API ЭПОСа. Живут внутри EposSession.
///
/// Основная аутентификация — cookies (aid, auth_token, long_token,
/// profile_id, is_auth, from_sudir, RSESSION, waf_cookie, SERVERID).
/// Auth-Token/Profile-Id — fallback для legacy-сессий без cookie-jar.
class EposTokens {
  final String authToken;
  final String profileId;

  /// Готовый Cookie-заголовок: "aid=14; auth_token=...; profile_id=...".
  /// Если пусто — ApiClient использует Auth-Token/Profile-Id.
  final String cookieHeader;

  EposTokens({
    required this.authToken,
    required this.profileId,
    this.cookieHeader = '',
  });
}
