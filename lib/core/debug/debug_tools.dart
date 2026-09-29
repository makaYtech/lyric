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

/// Снимок текущего состояния — чтобы UI показал одним куском и не
/// гонял по пять фьючеров на rebuild.
class DebugSnapshot {
  final EposSession? epos;
  final String? deviceKey;

  const DebugSnapshot({this.epos, this.deviceKey});

  bool get hasEposSession => epos != null;

  /// Все cookies активной сессии. Пустая мапа, если сессии нет.
  Map<String, String> get cookies => epos?.cookies ?? const {};
}

/// Утилиты для отладки: сброс отдельных частей состояния приложения.
/// Всё, что тут есть — деструктивно (или почти), вызывается только из
/// DeveloperScreen в настройках.
class DebugTools {
  DebugTools._();
  static final instance = DebugTools._();

  static const _eposBase = 'https://edu-epos.permkrai.ru';
  static const _userAgent = 'okhttp/4.12.0';

  final _cache = CacheService();

  // ── Снимок состояния ───────────────────────────────────────────────────

  Future<DebugSnapshot> snapshot() async {
    final epos = await SessionRefreshService.instance.load();
    final key = await DeviceTokenAuthService.instance.readDeviceKey();
    return DebugSnapshot(epos: epos, deviceKey: key);
  }

  // ── Отравление (испортить значение, сохранив ключ) ────────────────────

  /// Отравить одну cookie. Значение заменяется на маркер с timestamp,
  /// чтобы в UI сразу было видно, что это тест.
  Future<void> poisonCookie(String name) async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final updated = Map<String, String>.from(s.cookies);
    updated[name] = 'POISONED_${DateTime.now().millisecondsSinceEpoch}';
    final next = s.copyWith(cookies: updated);
    await _save(next);
  }

  /// Отравить device_token (UUID из ESIA). GET /authenticate на такой
  /// UUID вернёт 4xx → renew вернёт authDead → ReauthSheet.
  Future<void> poisonDeviceToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = s.copyWith(
      deviceToken: 'POISONED_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _save(next);
  }

  // ── Сброс (удалить значение) ──────────────────────────────────────────

  /// Убрать device_token. Сессия останется живой, пока cookies валидны,
  /// но первый же 401 приведёт к authDead (renew не сможет обновиться).
  Future<void> clearDeviceToken() async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return;
    final next = s.copyWith(deviceToken: '');
    await _save(next);
  }

  /// Убрать OAuth-пару (access + refresh + expires). Для legacy-сессий
  /// сломает refresh, для device-token — безвредно.
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
    );
    await _save(next);
  }

  /// Убрать long_token. Для API он балласт, так что эффекта не ждём.
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
    );
    await _save(next);
  }

  /// Полный снос сессии ЭПОС из памяти и защищённого хранилища.
  Future<void> clearWholeEposSession() async {
    AuthCoordinator.instance.clear();
    await SessionRefreshService.instance.clear();
    SessionNotifier.instance.reset();
  }

  // ── Прямой запрос в обход клиента ─────────────────────────────────────

  /// Отправить GET к ЭПОСу с текущими cookies, минуя ApiClient и
  /// AuthCoordinator. Renew не сработает даже на 401/403 — вернётся
  /// чистый ответ сервера. Нужно для проверки гипотез про WAF и
  /// отдельные cookies.
  Future<String> probe(String path) async {
    final s = await SessionRefreshService.instance.load();
    if (s == null) return 'Нет сессии';
    final client = await createEposRawHttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_eposBase$path'));
      if (s.cookieHeader.isNotEmpty) {
        req.headers.set('Cookie', s.cookieHeader);
      } else {
        req.headers.set('Auth-Token', s.authToken);
        req.headers.set('Profile-Id', s.profileId);
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

  // ── device_key ─────────────────────────────────────────────────────────

  Future<void> resetDeviceKey() =>
      DeviceTokenAuthService.instance.resetDeviceKey();

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
    await _cache.clearAll();
    AvatarStorage.invalidateAll();
    await AppDatabase.instance.clearAll();
    if (alsoDeviceKey) {
      await DeviceTokenAuthService.instance.resetDeviceKey();
    }
    SessionNotifier.instance.reset();
  }

  // ── Внутреннее ─────────────────────────────────────────────────────────

  /// Общая обвязка для сохранения изменённой сессии: пишем в storage,
  /// обновляем in-memory состояние AuthCoordinator, снимаем sticky-флаг
  /// «сессия истекла» (иначе тестовая отравленная сессия не даст UI
  /// показать актуальную картину).
  Future<void> _save(EposSession next) async {
    await SessionRefreshService.instance.save(next);
    AuthCoordinator.instance.setSession(next);
    SessionNotifier.instance.reset();
  }
}
