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

  /// id пользователя из cookie user_id. Нужен для /acl/api/users.
  final int? userId;

  EposTokens({
    required this.authToken,
    required this.profileId,
    this.cookieHeader = '',
    this.userId,
  });

  /// Те же токены, но от имени другого профиля (ребёнка родителя).
  EposTokens withProfile(String profileId) => EposTokens(
    authToken: authToken,
    profileId: profileId,
    cookieHeader: replaceCookieValue(cookieHeader, 'profile_id', profileId),
    userId: userId,
  );
}

/// Подменяет значение cookie в готовом заголовке, не трогая остальные.
String replaceCookieValue(String header, String name, String value) {
  if (header.isEmpty) return header;
  final parts = header.split('; ');
  var found = false;
  for (var i = 0; i < parts.length; i++) {
    final eq = parts[i].indexOf('=');
    if (eq <= 0) continue;
    if (parts[i].substring(0, eq) == name) {
      parts[i] = '$name=$value';
      found = true;
    }
  }
  if (!found) parts.add('$name=$value');
  return parts.join('; ');
}
