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
/// EposSession.tokens возвращает EposTokens — им пользуются
/// репозитории, ничего в них менять не надо.
class EposSession {
  /// Для запросов к /core/api и /jersey/api.
  final String authToken;
  final String profileId;

  /// OAuth-токены (client_id=auth).
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;

  /// Опционально — то, что может пригодиться позже.
  final String? longToken;
  final int? userId;

  const EposSession({
    required this.authToken,
    required this.profileId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    this.longToken,
    this.userId,
  });

  /// Совместимость со старым кодом.
  EposTokens get tokens =>
      EposTokens(authToken: authToken, profileId: profileId);

  /// За 2 минуты до истечения — уже пора обновлять.
  bool get needsRefresh =>
      DateTime.now().isAfter(
        accessExpiresAt.subtract(const Duration(minutes: 2)),
      );

  EposSession copyWith({
    String? authToken,
    String? profileId,
    String? accessToken,
    String? refreshToken,
    DateTime? accessExpiresAt,
    String? longToken,
    int? userId,
  }) => EposSession(
    authToken: authToken ?? this.authToken,
    profileId: profileId ?? this.profileId,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    accessExpiresAt: accessExpiresAt ?? this.accessExpiresAt,
    longToken: longToken ?? this.longToken,
    userId: userId ?? this.userId,
  );

  Map<String, dynamic> toJson() => {
    'auth_token': authToken,
    'profile_id': profileId,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'access_expires_at': accessExpiresAt.toIso8601String(),
    'long_token': longToken,
    'user_id': userId,
  };

  factory EposSession.fromJson(Map<String, dynamic> j) => EposSession(
    authToken: j['auth_token'] as String,
    profileId: j['profile_id'] as String,
    accessToken: j['access_token'] as String,
    refreshToken: j['refresh_token'] as String,
    accessExpiresAt: DateTime.parse(j['access_expires_at'] as String),
    longToken: j['long_token'] as String?,
    userId: j['user_id'] as int?,
  );
}