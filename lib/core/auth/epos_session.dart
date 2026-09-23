import '../../services/auth_service.dart';

/// Полная сессия ЭПОСа. Заменяет связку «EposTokens + отдельные поля».
///
/// Основной механизм аутентификации — cookies (aid, auth_token,
/// long_token, profile_id, is_auth, from_sudir, RSESSION, waf_cookie,
/// SERVERID), которые сервер устанавливает в /authenticate и
/// финализирующих запросах. Заголовки Auth-Token/Profile-Id —
/// fallback для legacy OAuth-сессий.
///
/// Что именно на руках — определяется наличием [deviceToken]:
///   deviceToken != null → новый flow, refresh = GET /authenticate
///   deviceToken == null → старый flow, refresh = OAuth refresh_token
class EposSession {
  /// UUID из diaryperm://redirect?token=...
  /// Нужен для POST /authenticate/student_profile (в body auth_token
  /// идёт ИМЕННО он, а не hex из cookie).
  final String authToken;

  final String profileId;

  /// UUID, который уходит в заголовке token при GET /authenticate.
  final String? deviceToken;

  /// Все cookies, установленные сервером. Ключ — имя, значение — значение.
  /// Формат хранения — Map, потому что при запросах порядок не важен,
  /// а обновление из Set-Cookie удобнее делать по имени.
  final Map<String, String> cookies;

  /// OAuth-токены (client_id=auth). Для device-token-сессии — null.
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessExpiresAt;

  /// Опционально — то, что может пригодиться позже.
  final String? longToken;
  final int? userId;

  const EposSession({
    required this.authToken,
    required this.profileId,
    this.deviceToken,
    this.cookies = const {},
    this.accessToken,
    this.refreshToken,
    this.accessExpiresAt,
    this.longToken,
    this.userId,
  });

  /// "aid=14; auth_token=...; profile_id=..." — то, что кладётся
  /// в заголовок Cookie.
  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Совместимость со старым кодом (ApiClient, сервисы).
  EposTokens get tokens => EposTokens(
    authToken: authToken,
    profileId: profileId,
    cookieHeader: cookieHeader,
  );

  /// Device-token-сессию не обновляем проактивно: её срок неизвестен.
  /// Ловим 401 от API — тогда AuthCoordinator сходит за свежими cookie.
  ///
  /// Legacy-сессию обновляем за 2 минуты до истечения access_token.
  bool get needsRefresh {
    if (deviceToken != null) return false;
    final exp = accessExpiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(minutes: 2)));
  }

  EposSession copyWith({
    String? authToken,
    String? profileId,
    String? deviceToken,
    Map<String, String>? cookies,
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    String? longToken,
    int? userId,
  }) => EposSession(
    authToken: authToken ?? this.authToken,
    profileId: profileId ?? this.profileId,
    deviceToken: deviceToken ?? this.deviceToken,
    cookies: cookies ?? this.cookies,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
    longToken: longToken ?? this.longToken,
    userId: userId ?? this.userId,
  );

  Map<String, dynamic> toJson() => {
    'auth_token': authToken,
    'profile_id': profileId,
    'device_token': deviceToken,
    'cookies': cookies,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'access_expires_at': accessExpiresAt?.toIso8601String(),
    'long_token': longToken,
    'user_id': userId,
  };

  factory EposSession.fromJson(Map<String, dynamic> j) {
    final expRaw = j['access_expires_at'];
    final rawCookies = j['cookies'];
    final cookies = <String, String>{};
    if (rawCookies is Map) {
      rawCookies.forEach((k, v) {
        if (k is String && v is String) cookies[k] = v;
      });
    }
    return EposSession(
      authToken: j['auth_token'] as String,
      profileId: j['profile_id'] as String,
      deviceToken: j['device_token'] as String?,
      cookies: cookies,
      accessToken: j['access_token'] as String?,
      refreshToken: j['refresh_token'] as String?,
      accessExpiresAt: expRaw is String ? DateTime.tryParse(expRaw) : null,
      longToken: j['long_token'] as String?,
      userId: j['user_id'] as int?,
    );
  }
}
