import '../../data/services/epos/auth_service.dart';

/// Полная сессия ЭПОСа.
///
/// Что на руках — определяется наличием [deviceToken]:
///   deviceToken непустой → device-token flow, refresh = GET /authenticate;
///   deviceToken null/''   → legacy OAuth, refresh = refresh_token.
class EposSession {
  /// UUID из diaryperm://redirect?token=... В POST /authenticate/student_profile
  /// в body auth_token идёт именно он, а не hex из cookie.
  final String authToken;

  final String profileId;

  /// UUID для заголовка token при GET /authenticate.
  final String? deviceToken;

  /// Все cookies сервера: имя → значение.
  final Map<String, String> cookies;

  /// OAuth-токены (client_id=auth). Для device-token-сессии — null.
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessExpiresAt;

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

  /// "aid=14; auth_token=...; profile_id=..." для заголовка Cookie.
  String get cookieHeader =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  EposTokens get tokens => EposTokens(
    authToken: authToken,
    profileId: profileId,
    cookieHeader: cookieHeader,
  );

  /// Device-token-сессию не обновляем проактивно: её срок неизвестен,
  /// ловим 401. Legacy обновляем за 2 минуты до истечения access_token.
  bool get needsRefresh {
    if (deviceToken?.isNotEmpty == true) return false;
    final exp = accessExpiresAt;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp.subtract(const Duration(minutes: 2)));
  }

  /// Для API нужны непустой deviceToken и auth_token/profile_id в cookies.
  bool get isCompleteForApi =>
      deviceToken?.isNotEmpty == true &&
      cookies.containsKey('auth_token') &&
      cookies.containsKey('profile_id');

  /// Нужно ли дотянуть cookies через exchange по deviceToken. Legacy-сессии
  /// сюда не попадают: они ходят через заголовки Auth-Token/Profile-Id.
  bool get needsCookieBackfill =>
      deviceToken?.isNotEmpty == true && !isCompleteForApi;

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
