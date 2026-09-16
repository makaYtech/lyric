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
///
/// Логика такая: «сбросить отдельный токен» = сделать сессию заведомо
/// неполной, чтобы посмотреть, как приложение себя поведёт при следующем
/// запросе. Например, убрать device_token → refresh невозможен → должен
/// появиться ReauthSheet. Это и нужно, чтобы проверять грабли.
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

  /// Убирает device_token. auth_token продолжает работать, но при первом
  /// 401 обновиться уже не сможем — упрёмся в ReauthSheet. Полезно, чтобы
  /// проверить, как приложение отрабатывает отсутствие device-token.
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

  /// Подменяет auth_token на заведомо мусорный. Следующий запрос к API
  /// отдаст 401 → AuthCoordinator попробует renew() → успех = устройство
  /// сессии живое, провал = уйдём в ReauthSheet.
  ///
  /// Именно так проверяется, что новый flow действительно «самовосста-
  /// навливается»: после яда должно само вылечиться за один 401.
  Future<void> poisonAuthToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = s.copyWith(authToken: 'INVALID_FOR_TEST');
    await SessionRefreshService.instance.save(updated);
    AuthCoordinator.instance.setSession(updated);
    SessionNotifier.instance.reset();
  }

  /// Обнуляет OAuth-пару (access + refresh + expires). Для device-token-
  /// сессии это no-op по последствиям (она их не использует), для
  /// legacy — сломает refresh.
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

  /// Стирает EposSession целиком (secure storage + память).
  /// Следующий запуск увидит отсутствие сессии и откроет LoginScreen.
  Future<void> clearWholeEposSession() async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    SessionNotifier.instance.reset();
  }

  // ── device_key ─────────────────────────────────────────────────────────

  /// Сбросить device_key. Следующий интерактивный вход сгенерирует новый.
  /// Старый ключ на сервере останется висеть — сам по себе он бесполезен
  /// без нашего UI, так что это безопасно.
  Future<void> resetDeviceKey() =>
      DeviceTokenAuthService.instance.resetDeviceKey();

  // ── Моя школа ──────────────────────────────────────────────────────────

  Future<void> clearMySchoolTokens() => MySchoolTokenStorage().clear();

  // ── Кэш (SharedPreferences) ────────────────────────────────────────────

  Future<void> clearProfileCache() => _cache.remove('profile');
  Future<void> clearAcademicYearsCache() => _cache.remove('academic_years');
  Future<void> clearStudentGroupsCache() =>
      _cache.remove('student_groups');

  /// Сносим только записи с префиксом avatar: — не трогая настройки
  /// приложения (theme_mode и прочее). После — обязательно сбрасываем
  /// in-memory кэш AvatarStorage, иначе в памяти останутся пути к файлам,
  /// ссылок на которые в prefs уже нет, и аватарки будут показываться
  /// «из ниоткуда» до перезапуска.
  Future<void> clearAvatarCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('avatar:'))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
    AvatarStorage.invalidateAll();
  }

  /// Сбросить prefs расписания/учителей/ДЗ к дефолтным значениям.
  /// Пишем значения по умолчанию прямо в prefs — так ValueNotifier'ы
  /// обновятся, а не останутся с прошлыми значениями до перезапуска.
  Future<void> resetDisplayPrefs() async {
    await _cache.saveInt('merge_lesson_pairs', 0);
    await _cache.saveInt('teacher_subjects_limit', 5);
    await _cache.saveInt('teacher_rooms_limit', 5);
    await _cache.saveInt('teacher_show_old_rooms', 0);
    await _cache.saveInt('teacher_only_student_teachers', 0);
    await _cache.saveInt('homework_group_by_due', 0);
  }

  /// Полный снос SharedPreferences кроме темы. Эквивалент
  /// CacheService.clearAll(), вынесен сюда для симметрии с UI.
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

  Future<void> clearHomeworks() =>
      AppDatabase.instance.clearTable(AppDatabase.tableHomeworks);

  Future<void> clearTeachers() =>
      AppDatabase.instance.clearTable(AppDatabase.tableTeachers);

  Future<void> clearWholeDatabase() => AppDatabase.instance.clearAll();

  // ── Действия ───────────────────────────────────────────────────────────

  /// Прогнать refresh сессии через AuthCoordinator вручную.
  /// Возвращает человекочитаемый результат — для snackbar'а.
  Future<String> forceSessionRefresh() async {
    final outcome = await AuthCoordinator.instance.renew();
    return switch (outcome) {
      RenewOutcome.success => 'Сессия обновлена',
      RenewOutcome.authDead => 'Сессия мертва — нужен перелогин',
      RenewOutcome.networkError => 'Сеть недоступна',
    };
  }

  // ── Полный сброс ───────────────────────────────────────────────────────

  /// «Как после переустановки, но без потери device_key и темы»:
  /// стирает сессию, кэш, prefs (кроме темы) и всю БД.
  /// device_key и theme_mode намеренно остаются — их потеря не входит
  /// в сценарий «сбросить данные пользователя».
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

/// Помощник для UI: не использовать в проде. Просто обёртка над
/// FlutterSecureStorage на случай, если понадобится что-то ещё
/// вытащить из хранилища руками.
Future<String?> _unusedReadSecure(String key) async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  return storage.read(key: key);
}