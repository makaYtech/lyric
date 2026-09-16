import '../../services/auth_service.dart';

/// Полная сессия ЭПОСа. Заменяет связку «EposTokens + отдельные поля».
///
/// Разделяем три уровня:
///   - auth_token/profile_id  — то, что видят все репозитории через
///                              EposTokens (совместимость не ломаем).
///   - access_token           — для OAuth-операций (refresh, exchange).
///   - refresh_token          — offline, бессрочный. Хранится в
///                              защищённом хранилище.
///
/// С появлением device-token-флоу (см. DeviceTokenAuthService) OAuth-поля
/// стали опциональными: device-token-сессия их не имеет вообще. Что
/// именно на руках — определяется наличием [deviceToken]:
///   deviceToken != null → новый flow, refresh = GET /authenticate
///   deviceToken == null → старый flow, refresh = OAuth refresh_token
class EposSession {
  /// Для запросов к /core/api и /jersey/api.
  final String authToken;
  final String profileId;

  /// Долгоживущий UUID из diaryperm://redirect?token=.
  final String? deviceToken;

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
    this.accessToken,
    this.refreshToken,
    this.accessExpiresAt,
    this.longToken,
    this.userId,
  });

  /// Совместимость со старым кодом.
  EposTokens get tokens =>
      EposTokens(authToken: authToken, profileId: profileId);

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
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    String? longToken,
    int? userId,
  }) => EposSession(
    authToken: authToken ?? this.authToken,
    profileId: profileId ?? this.profileId,
    deviceToken: deviceToken ?? this.deviceToken,
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
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'access_expires_at': accessExpiresAt?.toIso8601String(),
    'long_token': longToken,
    'user_id': userId,
  };

  factory EposSession.fromJson(Map<String, dynamic> j) {
    final expRaw = j['access_expires_at'];
    return EposSession(
      authToken: j['auth_token'] as String,
      profileId: j['profile_id'] as String,
      deviceToken: j['device_token'] as String?,
      accessToken: j['access_token'] as String?,
      refreshToken: j['refresh_token'] as String?,
      accessExpiresAt:
      expRaw is String ? DateTime.tryParse(expRaw) : null,
      longToken: j['long_token'] as String?,
      userId: j['user_id'] as int?,
    );
  }
}