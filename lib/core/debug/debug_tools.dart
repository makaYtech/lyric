import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_coordinator.dart';
import '../auth/device_token_auth.dart';
import '../auth/epos_session.dart';
import '../auth/session_notifier.dart';
import '../auth/session_refresh_service.dart';
import '../cache/cache_service.dart';
import '../db/app_database.dart';
import '../network/epos_http_client.dart';
import '../settings/avatar_storage.dart';

/// Снимок текущего состояния для UI — одним куском, без пяти фьючеров
/// на каждый rebuild.
class DebugSnapshot {
  final EposSession? epos;
  final String? deviceKey;

  const DebugSnapshot({this.epos, this.deviceKey});

  bool get hasEposSession => epos != null;

  /// Все cookies активной сессии. Пустая мапа, если сессии нет.
  Map<String, String> get cookies => epos?.cookies ?? const {};
}

/// Деструктивные утилиты для DeveloperScreen: сброс отдельных частей
/// состояния приложения.
class DebugTools {
  DebugTools._();
  static final instance = DebugTools._();

  static const _eposBase = 'https://edu-epos.permkrai.ru';
  static const _userAgent = 'okhttp/4.12.0';

  final _cache = CacheService();
  final _scopedCache = CacheService(scoped: true);

  Future<DebugSnapshot> snapshot() async {
    final epos = await SessionRefreshService.instance.load();
    final key = await DeviceTokenAuthService.instance.readDeviceKey();
    return DebugSnapshot(epos: epos, deviceKey: key);
  }

  /// Отравить одну cookie маркером с timestamp.
  Future<void> poisonCookie(String name) async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = Map<String, String>.from(s.cookies);
    updated[name] = 'POISONED_${DateTime.now().millisecondsSinceEpoch}';
    final next = s.copyWith(cookies: updated);
    await _save(next);
  }

  /// GET /authenticate на такой UUID вернёт 4xx → renew → authDead.
  Future<void> poisonDeviceToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = s.copyWith(
      deviceToken: 'POISONED_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _save(next);
  }

  /// Сессия живёт, пока cookies валидны, но первый же 401 даст authDead.
  Future<void> clearDeviceToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = s.copyWith(deviceToken: '');
    await _save(next);
  }

  /// Ломает refresh legacy-сессий, для device-token безвредно.
  Future<void> clearOauthPair() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = EposSession(
      authToken: s.authToken,
      profileId: s.profileId,
      deviceToken: s.deviceToken,
      cookies: s.cookies,
      accessToken: null,
      refreshToken: null,
      accessExpiresAt: null,
      longToken: s.longToken,
      userId: s.userId,
      activeProfileId: s.activeProfileId,
      accountType: s.accountType,
    );
    await _save(next);
  }

  /// Для API long_token — балласт, эффекта не ждём.
  Future<void> clearLongToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = EposSession(
      authToken: s.authToken,
      profileId: s.profileId,
      deviceToken: s.deviceToken,
      cookies: s.cookies,
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      accessExpiresAt: s.accessExpiresAt,
      longToken: null,
      userId: s.userId,
      activeProfileId: s.activeProfileId,
      accountType: s.accountType,
    );
    await _save(next);
  }

  /// Полный снос сессии ЭПОС из памяти и защищённого хранилища.
  Future<void> clearWholeEposSession() async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    SessionNotifier.instance.reset();
  }

  /// GET к ЭПОСу с текущими cookies, минуя ApiClient и AuthCoordinator:
  /// renew не сработает даже на 401/403. Для проверки гипотез про WAF.
  Future<String> probe(String path) async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return 'Нет сессии';
    final client = await createEposRawHttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_eposBase$path'));
      final tokens = s.tokens;
      if (tokens.cookieHeader.isNotEmpty) {
        req.headers.set('Cookie', tokens.cookieHeader);
      } else {
        req.headers.set('Auth-Token', tokens.authToken);
        req.headers.set('Profile-Id', tokens.profileId);
      }
      req.headers.set('User-Agent', _userAgent);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      await resp.drain<void>();
      return 'HTTP ${resp.statusCode}';
    } catch (e) {
      return 'Ошибка: $e';
    } finally {
      client.close(force: true);
    }
  }

  Future<void> resetDeviceKey() =>
      DeviceTokenAuthService.instance.resetDeviceKey();

  Future<void> clearProfileCache() => _scopedCache.remove('profile');
  Future<void> clearAcademicYearsCache() =>
      _scopedCache.remove('academic_years');
  Future<void> clearStudentGroupsCache() =>
      _scopedCache.remove('student_groups');

  Future<void> clearAvatarCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('avatar:')).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    AvatarStorage.invalidateAll();
  }

  Future<void> resetDisplayPrefs() async {
    await _cache.saveInt('merge_lesson_pairs', 0);
    await _cache.saveInt('teacher_subjects_limit', 5);
    await _cache.saveInt('teacher_rooms_limit', 5);
    await _cache.saveInt('teacher_show_old_rooms', 0);
    await _cache.saveInt('teacher_only_student_teachers', 0);
    await _cache.saveInt('homework_group_by_due', 0);
  }

  Future<void> clearAllSharedPrefs() async {
    await _cache.clearAll();
    AvatarStorage.invalidateAll();
  }

  Future<void> clearLessons() =>
      AppDatabase.instance.clearTable(AppDatabase.tableLessons);

  Future<void> clearGrades() async {
    await AppDatabase.instance.clearTable(AppDatabase.tableGrades);
    await AppDatabase.instance.clearTable(AppDatabase.tableGradeHistory);
  }

  Future<void> clearMarks() =>
      AppDatabase.instance.clearTable(AppDatabase.tableMarks);

  Future<void> clearAttendances() =>
      AppDatabase.instance.clearTable(AppDatabase.tableAttendances);

  Future<void> clearHomeworks() =>
      AppDatabase.instance.clearTable(AppDatabase.tableHomeworks);

  Future<void> clearTeachers() =>
      AppDatabase.instance.clearTable(AppDatabase.tableTeachers);

  Future<void> clearWholeDatabase() => AppDatabase.instance.clearAll();

  Future<String> forceSessionRefresh() async {
    final outcome = await AuthCoordinator.instance.renew();
    return switch (outcome) {
      RenewOutcome.success => 'Сессия обновлена',
      RenewOutcome.authDead => 'Сессия мертва — нужен перелогин',
      RenewOutcome.networkError => 'Сеть недоступна',
    };
  }

  Future<void> fullWipe({bool alsoDeviceKey = false}) async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    await _cache.clearAll();
    AvatarStorage.invalidateAll();
    await AppDatabase.instance.clearAllProfiles();
    if (alsoDeviceKey) {
      await DeviceTokenAuthService.instance.resetDeviceKey();
    }
    SessionNotifier.instance.reset();
  }

  /// Сохраняет сессию, обновляет in-memory состояние AuthCoordinator и
  /// снимает sticky-флаг «сессия истекла», иначе UI не покажет новую картину.
  Future<void> _save(EposSession next) async {
    await SessionRefreshService.instance.save(next);
    AuthCoordinator.instance.setSession(next);
    SessionNotifier.instance.reset();
  }
}
