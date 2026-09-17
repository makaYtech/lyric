import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_coordinator.dart';
import '../auth/device_token_auth.dart';
import '../auth/epos_session.dart';
import '../auth/myschool_token_storage.dart';
import '../auth/session_notifier.dart';
import '../auth/session_refresh_service.dart';
import '../cache/cache_service.dart';
import '../db/app_database.dart';
import '../settings/avatar_storage.dart';

/// Снимок текущего состояния — чтобы UI показал одним куском и не
/// гонял по пять фьючеров на rebuild.
class DebugSnapshot {
  final EposSession? epos;
  final String? deviceKey;
  final bool mySchoolTokensPresent;

  const DebugSnapshot({
    this.epos,
    this.deviceKey,
    this.mySchoolTokensPresent = false,
  });

  bool get hasEposSession => epos != null;
}

/// Утилиты для отладки: сброс отдельных частей состояния приложения.
/// Всё, что тут есть — деструктивно (или почти), вызывается только из
/// DeveloperScreen в настройках.
class DebugTools {
  DebugTools._();
  static final instance = DebugTools._();

  final _cache = CacheService();

  // ── Снимок состояния ───────────────────────────────────────────────────

  Future<DebugSnapshot> snapshot() async {
    final epos = await SessionRefreshService.instance.load();
    final key = await DeviceTokenAuthService.instance.readDeviceKey();
    final ms = await MySchoolTokenStorage().load();
    return DebugSnapshot(
      epos: epos,
      deviceKey: key,
      mySchoolTokensPresent: ms != null,
    );
  }

  // ── Сессия ЭПОС: точечные сбросы ──────────────────────────────────────

  Future<void> clearDeviceToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = EposSession(
      authToken: s.authToken,
      profileId: s.profileId,
      deviceToken: null,
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      accessExpiresAt: s.accessExpiresAt,
      longToken: s.longToken,
      userId: s.userId,
    );
    await SessionRefreshService.instance.save(updated);
    AuthCoordinator.instance.setSession(updated);
    SessionNotifier.instance.reset();
  }

  Future<void> poisonAuthToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = s.copyWith(authToken: 'INVALID_FOR_TEST');
    await SessionRefreshService.instance.save(updated);
    AuthCoordinator.instance.setSession(updated);
    SessionNotifier.instance.reset();
  }

  Future<void> clearOauthPair() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = EposSession(
      authToken: s.authToken,
      profileId: s.profileId,
      deviceToken: s.deviceToken,
      accessToken: null,
      refreshToken: null,
      accessExpiresAt: null,
      longToken: s.longToken,
      userId: s.userId,
    );
    await SessionRefreshService.instance.save(updated);
    AuthCoordinator.instance.setSession(updated);
  }

  Future<void> clearLongToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = EposSession(
      authToken: s.authToken,
      profileId: s.profileId,
      deviceToken: s.deviceToken,
      accessToken: s.accessToken,
      refreshToken: s.refreshToken,
      accessExpiresAt: s.accessExpiresAt,
      longToken: null,
      userId: s.userId,
    );
    await SessionRefreshService.instance.save(updated);
    AuthCoordinator.instance.setSession(updated);
  }

  Future<void> clearWholeEposSession() async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    SessionNotifier.instance.reset();
  }

  // ── device_key ─────────────────────────────────────────────────────────

  Future<void> resetDeviceKey() =>
      DeviceTokenAuthService.instance.resetDeviceKey();

  // ── Моя школа ──────────────────────────────────────────────────────────

  Future<void> clearMySchoolTokens() => MySchoolTokenStorage().clear();

  // ── Кэш (SharedPreferences) ────────────────────────────────────────────

  Future<void> clearProfileCache() => _cache.remove('profile');
  Future<void> clearAcademicYearsCache() => _cache.remove('academic_years');
  Future<void> clearStudentGroupsCache() => _cache.remove('student_groups');

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

  // ── SQLite ─────────────────────────────────────────────────────────────

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

  // ── Действия ───────────────────────────────────────────────────────────

  Future<String> forceSessionRefresh() async {
    final outcome = await AuthCoordinator.instance.renew();
    return switch (outcome) {
      RenewOutcome.success => 'Сессия обновлена',
      RenewOutcome.authDead => 'Сессия мертва — нужен перелогин',
      RenewOutcome.networkError => 'Сеть недоступна',
    };
  }

  // ── Полный сброс ───────────────────────────────────────────────────────

  Future<void> fullWipe({bool alsoDeviceKey = false}) async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    await MySchoolTokenStorage().clear();
    await _cache.clearAll();
    AvatarStorage.invalidateAll();
    await AppDatabase.instance.clearAll();
    if (alsoDeviceKey) {
      await DeviceTokenAuthService.instance.resetDeviceKey();
    }
    SessionNotifier.instance.reset();
  }
}

/// Помощник для UI: не использовать в проде.
Future<String?> _unusedReadSecure(String key) async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  return storage.read(key: key);
}
