import 'package:flutter/foundation.dart';

import '../core/auth/epos_session.dart';
import '../core/auth/session_notifier.dart';
import '../core/auth/session_refresh_service.dart';
import '../core/cache/cache_service.dart';
import '../core/settings/homework_prefs.dart';
import '../core/settings/schedule_prefs.dart';
import '../core/settings/teacher_prefs.dart';
import '../models/academic_year.dart';
import '../models/attendance.dart';
import '../models/bells_timetable.dart';
import '../models/day_schedule.dart';
import '../models/homework.dart';
import '../models/lesson.dart';
import '../models/mark.dart';
import '../models/schedule_override.dart';
import '../models/student_profile.dart';
import '../models/subject_grade.dart';
import '../models/teacher.dart';
import '../repositories/academic_years_repository.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/bells_repository.dart';
import '../repositories/grades_repository.dart';
import '../repositories/homework_repository.dart';
import '../repositories/marks_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/student_groups_repository.dart';
import '../repositories/teachers_repository.dart';
import '../services/auth_service.dart';
import '../services/session_expired_exception.dart';
import '../core/auth/auth_coordinator.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required this._session,
    required void Function(String message) onError,
    ProfileRepository? profileRepository,
    GradesRepository? gradesRepository,
    AcademicYearsRepository? yearsRepository,
    ScheduleRepository? scheduleRepository,
    StudentGroupsRepository? groupsRepository,
    MarksRepository? marksRepository,
    HomeworkRepository? homeworkRepository,
    TeachersRepository? teachersRepository,
    BellsRepository? bellsRepository,
    AttendanceRepository? attendanceRepository,
    CacheService? cache,
  }) : _onError = onError,
       _profileRepository = profileRepository ?? ProfileRepository(),
       _gradesRepository = gradesRepository ?? GradesRepository(),
       _yearsRepository = yearsRepository ?? AcademicYearsRepository(),
       _scheduleRepository = scheduleRepository ?? ScheduleRepository(),
       _groupsRepository = groupsRepository ?? StudentGroupsRepository(),
       _marksRepository = marksRepository ?? MarksRepository(),
       _homeworkRepository = homeworkRepository ?? HomeworkRepository(),
       _teachersRepository = teachersRepository ?? TeachersRepository(),
       _bellsRepository = bellsRepository ?? BellsRepository(),
       _attendanceRepository = attendanceRepository ?? AttendanceRepository(),
       _cache = cache ?? CacheService() {
    _weekStart = _currentMonday();
  }

  EposSession _session;
  EposSession get session => AuthCoordinator.instance.session ?? _session;
  EposTokens get tokens => session.tokens;

  final void Function(String message) _onError;

  final ProfileRepository _profileRepository;
  final GradesRepository _gradesRepository;
  final AcademicYearsRepository _yearsRepository;
  final ScheduleRepository _scheduleRepository;
  final StudentGroupsRepository _groupsRepository;
  final MarksRepository _marksRepository;
  final HomeworkRepository _homeworkRepository;
  final TeachersRepository _teachersRepository;
  final BellsRepository _bellsRepository;
  final AttendanceRepository _attendanceRepository;
  final CacheService _cache;

  static const _selectedYearKey = 'selected_academic_year_id';
  static const _studentTeacherIdsKey = 'student_teacher_ids';
  static const _fallbackYearId = 14;
  static const _bellsTimetableIdFallback = 124412;

  static const titles = ['Профиль', 'Оценки', 'Расписание', 'ДЗ'];

  bool _disposed = false;

  /// Токены «отмены» для асинхронных операций. Инкрементируются при
  /// каждом новом запуске того же типа операции. Каждый await в теле
  /// проверяет, что его токен всё ещё актуален — иначе выходит, не
  /// затирая поля свежими-но-устаревшими данными.
  int _weekToken = 0;
  int _yearToken = 0;
  int _bellsToken = 0;
  int _scheduleToken = 0;

  final profileTick = ValueNotifier<int>(0);
  final gradesTick = ValueNotifier<int>(0);
  final scheduleTick = ValueNotifier<int>(0);
  final homeworksTick = ValueNotifier<int>(0);

  int _tabIndex = 0;
  int get tabIndex => _tabIndex;

  StudentProfile? _profile;
  StudentProfile? get profile => _profile;
  DateTime? _profileUpdated;
  DateTime? get profileUpdated => _profileUpdated;
  bool _profileLoading = true;
  bool get profileLoading => _profileLoading;
  String? _profileError;
  String? get profileError => _profileError;

  List<Teacher>? _teachers;
  List<Teacher>? get teachers => _teachers;
  DateTime? _teachersUpdated;
  DateTime? get teachersUpdated => _teachersUpdated;
  bool _teachersLoading = true;
  bool get teachersLoading => _teachersLoading;
  String? _teachersError;
  String? get teachersError => _teachersError;

  Set<int> _studentTeacherIds = <int>{};
  Set<int> get studentTeacherIds => _studentTeacherIds;

  List<SubjectGrade>? _grades;
  List<SubjectGrade>? get grades => _grades;
  DateTime? _gradesUpdated;
  DateTime? get gradesUpdated => _gradesUpdated;
  bool _gradesLoading = true;
  bool get gradesLoading => _gradesLoading;
  String? _gradesError;
  String? get gradesError => _gradesError;

  List<AcademicYear>? _years;
  List<AcademicYear>? get years => _years;
  int _selectedYearId = _fallbackYearId;
  int get selectedYearId => _selectedYearId;

  List<int> _groupIds = [];

  List<DaySchedule>? _schedule;
  List<DaySchedule>? get schedule => _schedule;
  DateTime? _scheduleUpdated;
  DateTime? get scheduleUpdated => _scheduleUpdated;
  bool _scheduleLoading = true;
  bool get scheduleLoading => _scheduleLoading;
  String? _scheduleError;
  String? get scheduleError => _scheduleError;

  BellsTimetable? _bells;
  BellsTimetable? get bells => _bells;

  Set<String> _daysWithOverrides = const {};
  Set<String> get daysWithOverrides => _daysWithOverrides;

  Set<int> _changedLessonIds = const {};
  Set<int> get changedLessonIds => _changedLessonIds;

  List<Mark>? _marks;
  List<Mark>? get marks => _marks;

  List<Attendance>? _attendances;
  List<Attendance>? get attendances => _attendances;

  List<Homework>? _homeworks;
  List<Homework>? get homeworks => _homeworks;
  DateTime? _homeworksUpdated;
  DateTime? get homeworksUpdated => _homeworksUpdated;
  bool _homeworksLoading = true;
  bool get homeworksLoading => _homeworksLoading;
  String? _homeworksError;
  String? get homeworksError => _homeworksError;

  late DateTime _weekStart;
  DateTime get weekStart => _weekStart;

  /// true — расписание уже один раз проскроллилось на текущий день
  /// в этом сеансе приложения. Сбрасывается при холодном старте.
  bool _scheduleAutoScrolledOnce = false;
  bool get scheduleAutoScrolledOnce => _scheduleAutoScrolledOnce;

  void markScheduleAutoScrolled() {
    if (_scheduleAutoScrolledOnce) return;
    _scheduleAutoScrolledOnce = true;
    // Колбэк приходит из initState/didUpdateWidget ScheduleView, то есть
    // во время фазы build. Синхронный notifyListeners отсюда уронит
    // markNeedsBuild() на уже построенных предках (AppBar, BottomBar).
    // Откладываем на микротаск — он выполнится сразу после текущего build.
    Future.microtask(() {
      if (!_disposed) _notify();
    });
  }

  bool get needsAuth => SessionNotifier.instance.needsAuth;

  String get currentTitle => titles[_tabIndex];

  bool get currentLoading => switch (_tabIndex) {
    0 => _profileLoading,
    1 => _gradesLoading,
    2 => _scheduleLoading,
    3 => _homeworksLoading,
    _ => false,
  };

  bool get anyLoading =>
      _profileLoading ||
      _gradesLoading ||
      _scheduleLoading ||
      _homeworksLoading ||
      _teachersLoading;

  String? get profileErrorForView => _profile == null ? _profileError : null;
  String? get gradesErrorForView =>
      (_grades == null || _grades!.isEmpty) ? _gradesError : null;
  String? get scheduleErrorForView =>
      (_schedule == null || _schedule!.isEmpty) ? _scheduleError : null;
  String? get homeworksErrorForView =>
      (_homeworks == null || _homeworks!.isEmpty) ? _homeworksError : null;

  // ── Жизненный цикл ─────────────────────────────────────────────────────

  Future<void> init() async {
    await SchedulePrefs.load();
    await HomeworkPrefs.load();
    await TeacherPrefs.load();
    SchedulePrefs.showOverrides.addListener(_onShowOverridesChanged);

    try {
      await _loadCachedAll();
    } catch (e) {
      debugPrint('Кэш не загрузился: $e');
    }
    await _ensureSessionComplete();
    await _loadBells();
    await refreshAll();
  }

  /// Если в хранилище лежит сессия нового flow без cookies (или без
  /// ключевых auth_token/profile_id) — прогоняем exchange через
  /// AuthCoordinator. Типичный случай: пользователь обновился со старой
  /// версии приложения, которая cookies не сохраняла.
  ///
  /// Если backfill не удался (сеть/authDead) — молча идём дальше:
  /// refreshAll() всё равно поймает 401 и сработает обычный путь renew,
  /// а при authDead покажется reauth-sheet.
  Future<void> _ensureSessionComplete() async {
    final current = AuthCoordinator.instance.session ?? _session;
    if (!current.needsCookieBackfill) return;
    try {
      await AuthCoordinator.instance.renew();
    } catch (e) {
      debugPrint('backfill cookies не удался: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Инвалидируем все токены, чтобы висящие await'ы не дописали ничего.
    _weekToken++;
    _yearToken++;
    _bellsToken++;
    _scheduleToken++;
    SchedulePrefs.showOverrides.removeListener(_onShowOverridesChanged);
    profileTick.dispose();
    gradesTick.dispose();
    scheduleTick.dispose();
    homeworksTick.dispose();
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _onShowOverridesChanged() {
    refreshSchedule(silent: true);
  }

  void setTabIndex(int i) {
    if (i == _tabIndex) return;
    _tabIndex = i;
    profileTick.value++;
    gradesTick.value++;
    scheduleTick.value++;
    homeworksTick.value++;
    _notify();
  }

  Future<void> updateSession(EposSession session) async {
    _session = session;
    AuthCoordinator.instance.setSession(session);
    await SessionRefreshService.instance.save(session);
    SessionNotifier.instance.clear();
    _notify();
  }

  // ── Bells ──────────────────────────────────────────────────────────────

  Future<void> _loadBells() async {
    final myToken = ++_bellsToken;
    try {
      final cached = await _bellsRepository.loadCached(_selectedYearId);
      if (myToken != _bellsToken || _disposed) return;
      if (cached != null) {
        _bells = cached;
        scheduleTick.value++;
        _notify();
      }

      final updated = await _bellsRepository.lastUpdated(_selectedYearId);
      if (myToken != _bellsToken || _disposed) return;
      final stale =
          updated == null || DateTime.now().difference(updated).inHours > 24;
      if (cached != null && !stale) return;

      final fresh = await _bellsRepository.refresh(
        tokens,
        timetableId: _bellsTimetableIdFallback,
        academicYearId: _selectedYearId,
      );
      if (myToken != _bellsToken || _disposed) return;
      _bells = fresh;
      scheduleTick.value++;
      _notify();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
    } catch (e) {
      debugPrint('bells не загрузились: $e');
    }
  }

  // ── Кэш ────────────────────────────────────────────────────────────────

  Future<void> _loadCachedAll() async {
    final profileFut = _profileRepository.loadCached();
    final profileUpdFut = _profileRepository.lastUpdated();
    final yearsFut = _yearsRepository.loadCached();
    final groupsFut = _groupsRepository.loadCached();
    final yearIdFut = _cache.loadInt(_selectedYearKey);
    final teacherIdsFut = _cache.loadString(_studentTeacherIdsKey);

    final profile = await profileFut;
    final profileUpdated = await profileUpdFut;
    final years = await yearsFut;
    final groups = await groupsFut;
    final savedYearId = await yearIdFut;
    final teacherIdsRaw = await teacherIdsFut;

    if (teacherIdsRaw != null && teacherIdsRaw.isNotEmpty) {
      _studentTeacherIds = teacherIdsRaw
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    }

    final yearId = savedYearId ?? _currentYearIdFrom(years) ?? _fallbackYearId;

    final gradesFut = _gradesRepository.loadCached(yearId);
    final gradesUpdFut = _gradesRepository.lastUpdated(yearId);
    final scheduleFut = _scheduleRepository.loadCached(_weekStart, yearId);
    final scheduleUpdFut = _scheduleRepository.lastUpdated(_weekStart, yearId);
    final marksFut = _marksRepository.loadCached(yearId, _weekStart);
    final attendancesFut = _attendanceRepository.loadCached(yearId);
    final homeworksFut = _homeworkRepository.loadCached(yearId);
    final homeworksUpdFut = _homeworkRepository.lastUpdated(yearId);
    final teachersFut = _teachersRepository.loadCached(yearId);
    final teachersUpdFut = _teachersRepository.lastUpdated(yearId);

    final grades = await gradesFut;
    final gradesUpdated = await gradesUpdFut;
    final schedule = await scheduleFut;
    final scheduleUpdated = await scheduleUpdFut;
    final marks = await marksFut;
    final attendances = await attendancesFut;
    final homeworks = await homeworksFut;
    final homeworksUpdated = await homeworksUpdFut;
    final teachers = await teachersFut;
    final teachersUpdated = await teachersUpdFut;

    if (_disposed) return;
    _profile = profile;
    _profileUpdated = profileUpdated;
    _years = years;
    _groupIds = (groups ?? const []).map((g) => g.id).toList();
    _selectedYearId = yearId;
    _grades = grades;
    _gradesUpdated = gradesUpdated;
    _schedule = schedule;
    _scheduleUpdated = scheduleUpdated;
    _marks = marks.isEmpty ? null : marks;
    _attendances = attendances.isEmpty ? null : attendances;
    _homeworks = homeworks;
    _homeworksUpdated = homeworksUpdated;
    _teachers = teachers;
    _teachersUpdated = teachersUpdated;

    _daysWithOverrides = await _scheduleRepository.loadDaysWithOverrides(
      _weekStart,
      yearId,
    );
    final cachedOverrides = await _scheduleRepository.loadWeekOverrides(
      _weekStart,
      yearId,
    );
    _changedLessonIds = SchedulePrefs.showOverrides.value
        ? _changedIdsFrom(cachedOverrides)
        : const {};

    _notify();
    profileTick.value++;
    gradesTick.value++;
    scheduleTick.value++;
    homeworksTick.value++;
  }

  int? _currentYearIdFrom(List<AcademicYear>? years) {
    if (years == null) return null;
    for (final y in years) {
      if (y.currentYear) return y.id;
    }
    return null;
  }

  // ── Обновления ─────────────────────────────────────────────────────────

  Future<void> _runRefresh({
    required void Function(bool) setLoading,
    required void Function(String?) setError,
    required ValueNotifier<int> revision,
    required Future<void> Function() body,
    required String errorToast,
    required bool silent,
  }) async {
    setLoading(true);
    setError(null);
    revision.value++;
    _notify();

    Future<void> runBody() => body();

    try {
      await runBody();
    } catch (e) {
      if (_disposed) return;
      setError('Не удалось обновить: $e');
      if (!silent) _onError(errorToast);
    } finally {
      if (!_disposed) {
        setLoading(false);
        revision.value++;
        _notify();
      }
    }
  }

  Future<void> refreshAll() async {
    await _refreshYears();
    await Future.wait([
      refreshProfile(),
      refreshGrades(),
      refreshSchedule(),
      refreshHomeworks(),
      _refreshTeachers(),
      refreshAttendances(),
    ]);
  }

  Future<void> refreshProfile({bool silent = false}) => _runRefresh(
    setLoading: (v) => _profileLoading = v,
    setError: (e) => _profileError = e,
    revision: profileTick,
    body: () async {
      final profile = await _profileRepository.refresh(tokens);
      final updated = await _profileRepository.lastUpdated();
      if (_disposed) return;
      _profile = profile;
      _profileUpdated = updated;
    },
    errorToast: 'Не удалось обновить профиль',
    silent: silent,
  );

  Future<void> _refreshTeachers() async {
    final yearId = _selectedYearId;
    _teachersLoading = true;
    profileTick.value++;
    _notify();
    try {
      final list = await _teachersRepository.refresh(tokens, yearId);
      if (_disposed || yearId != _selectedYearId) return;
      final updated = await _teachersRepository.lastUpdated(yearId);
      if (_disposed || yearId != _selectedYearId) return;
      _teachers = list;
      _teachersUpdated = updated;
      _teachersError = null;
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
    } catch (e) {
      if (_disposed || yearId != _selectedYearId) return;
      _teachersError = 'Не удалось обновить: $e';
    } finally {
      if (!_disposed && yearId == _selectedYearId) {
        _teachersLoading = false;
        profileTick.value++;
        _notify();
      }
    }
  }

  Future<void> _refreshYears() async {
    try {
      final years = await _yearsRepository.refresh(tokens);
      if (_disposed) return;

      var selected = _selectedYearId;
      if (!years.any((y) => y.id == selected)) {
        selected = _currentYearIdFrom(years) ?? _fallbackYearId;
        await _cache.saveInt(_selectedYearKey, selected);
      }
      if (_disposed) return;
      _years = years;
      _selectedYearId = selected;
      _notify();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
    } catch (_) {}
  }

  Future<void> refreshGrades({bool silent = false}) => _runRefresh(
    setLoading: (v) => _gradesLoading = v,
    setError: (e) => _gradesError = e,
    revision: gradesTick,
    body: () async {
      final yearId = _selectedYearId;
      final grades = await _gradesRepository.refresh(tokens, yearId);
      if (_disposed || yearId != _selectedYearId) return;
      final updated = await _gradesRepository.lastUpdated(yearId);
      if (_disposed || yearId != _selectedYearId) return;
      _grades = grades;
      _gradesUpdated = updated;
    },
    errorToast: 'Не удалось обновить оценки',
    silent: silent,
  );

  /// Отсутствия обновляем только в refreshAll: ручка отдаёт весь год
  /// разом. При смене недели не дёргаем — берём из кэша.
  Future<void> refreshAttendances({bool silent = false}) async {
    final yearId = _selectedYearId;
    try {
      final list = await _attendanceRepository.refresh(tokens, yearId);
      if (_disposed || yearId != _selectedYearId) return;
      _attendances = list.isEmpty ? null : list;
      scheduleTick.value++;
      _notify();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
    } catch (e) {
      if (!silent) debugPrint('attendances не загрузились: $e');
    }
  }

  Future<void> _ensureGroups() async {
    if (_groupIds.isNotEmpty) return;
    try {
      final groups = await _groupsRepository.refresh(tokens);
      if (_disposed) return;
      _groupIds = groups.map((g) => g.id).toList();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
      rethrow;
    } catch (_) {}
  }

  Future<void> refreshSchedule({bool silent = false}) {
    final myToken = ++_scheduleToken;
    return _runRefresh(
      setLoading: (v) => _scheduleLoading = v,
      setError: (e) => _scheduleError = e,
      revision: scheduleTick,
      body: () async {
        await _ensureGroups();
        if (myToken != _scheduleToken || _disposed) return;
        if (_groupIds.isEmpty) {
          throw Exception('не удалось получить список групп ученика');
        }
        final monday = _weekStart;
        final sunday = monday.add(const Duration(days: 6));
        final yearId = _selectedYearId;

        final results = await Future.wait<Object>([
          _scheduleRepository.refresh(tokens, monday, yearId, _groupIds),
          _marksRepository.refresh(tokens, yearId, from: monday, to: sunday),
        ]);
        if (myToken != _scheduleToken || _disposed) return;
        if (yearId != _selectedYearId || monday != _weekStart) return;

        final schedule = results[0] as List<DaySchedule>;
        final marks = results[1] as List<Mark>;

        final updated = await _scheduleRepository.lastUpdated(monday, yearId);
        if (myToken != _scheduleToken || _disposed) return;
        if (yearId != _selectedYearId || monday != _weekStart) return;

        final newIds = <int>{..._studentTeacherIds};
        for (final day in schedule) {
          for (final l in day.lessons) {
            final tid = l.teacherId;
            if (tid != null) newIds.add(tid);
          }
        }
        if (newIds.length != _studentTeacherIds.length) {
          _studentTeacherIds = newIds;
          await _cache.saveString(_studentTeacherIdsKey, newIds.join(','));
        }

        _schedule = schedule;
        _marks = marks;
        _scheduleUpdated = updated;
        await _refreshOverridesMeta();
      },
      errorToast: 'Не удалось обновить расписание',
      silent: silent,
    );
  }

  Future<void> refreshHomeworks({bool silent = false}) => _runRefresh(
    setLoading: (v) => _homeworksLoading = v,
    setError: (e) => _homeworksError = e,
    revision: homeworksTick,
    body: () async {
      final yearId = _selectedYearId;
      final range = _academicYearRange(DateTime.now());
      final homeworks = await _homeworkRepository.refresh(
        tokens,
        yearId,
        from: range.$1,
        to: range.$2,
      );
      if (_disposed || yearId != _selectedYearId) return;
      final updated = await _homeworkRepository.lastUpdated(yearId);
      if (_disposed || yearId != _selectedYearId) return;
      _homeworks = homeworks;
      _homeworksUpdated = updated;
    },
    errorToast: 'Не удалось обновить ДЗ',
    silent: silent,
  );

  static (DateTime, DateTime) _academicYearRange(DateTime today) {
    final year = today.month >= 9 ? today.year : today.year - 1;
    return (DateTime(year, 9, 1), DateTime(year + 1, 8, 31));
  }

  // ── Правки расписания ─────────────────────────────────────────────────

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Set<int> _changedIdsFrom(List<ScheduleOverride> overrides) {
    final out = <int>{};
    for (final o in overrides) {
      switch (o.kind) {
        case ScheduleOverrideKind.delete:
        case ScheduleOverrideKind.move:
          out.add(o.primaryLessonId);
        case ScheduleOverrideKind.pairBreak:
        case ScheduleOverrideKind.pairMake:
          out.add(o.primaryLessonId);
          final s = o.secondaryLessonId;
          if (s != null) out.add(s);
        case ScheduleOverrideKind.reorder:
          out.addAll(o.reorderOrder());
      }
    }
    return out;
  }

  Future<void> _refreshOverridesMeta() async {
    if (!SchedulePrefs.showOverrides.value) {
      if (_disposed) return;
      _daysWithOverrides = const {};
      _changedLessonIds = const {};
      return;
    }
    final overrides = await _scheduleRepository.loadWeekOverrides(
      _weekStart,
      _selectedYearId,
    );
    if (_disposed) return;
    _daysWithOverrides = overrides.map((o) => _isoDate(o.date)).toSet();
    _changedLessonIds = _changedIdsFrom(overrides);
  }

  Future<void> _reloadScheduleFromCache() async {
    final cached = await _scheduleRepository.loadCached(
      _weekStart,
      _selectedYearId,
    );
    final updated = await _scheduleRepository.lastUpdated(
      _weekStart,
      _selectedYearId,
    );

    if (_disposed) return;
    if (cached != null) {
      _schedule = cached;
    }
    _scheduleUpdated = updated;
    await _refreshOverridesMeta();
    if (_disposed) return;
    scheduleTick.value++;
    _notify();
  }

  Future<List<int>> deleteScheduleLessons({
    required DateTime date,
    required Iterable<int> lessonIds,
  }) async {
    final ids = lessonIds.toList();
    if (ids.isEmpty) return const [];

    final overrideIds = await _scheduleRepository.markDeletedMany(
      yearId: _selectedYearId,
      date: date,
      lessonIds: ids,
    );

    await _reloadScheduleFromCache();
    return overrideIds;
  }

  /// Пакетный перенос уроков в конкретные слоты (drop на окно).
  Future<List<int>> moveScheduleLessons({
    required DateTime date,
    required List<({int lessonId, String startTime, String endTime})> moves,
  }) async {
    if (moves.isEmpty) return const [];
    final ids = await _scheduleRepository.moveLessons(
      yearId: _selectedYearId,
      date: date,
      moves: moves,
    );
    await _reloadScheduleFromCache();
    return ids;
  }

  Future<void> breakSchedulePair({
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) async {
    await _scheduleRepository.breakPair(
      yearId: _selectedYearId,
      date: date,
      primaryId: primaryId,
      secondaryId: secondaryId,
    );
    await _reloadScheduleFromCache();
  }

  Future<void> makeSchedulePair({
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) async {
    await _scheduleRepository.makePair(
      yearId: _selectedYearId,
      date: date,
      primaryId: primaryId,
      secondaryId: secondaryId,
    );
    await _reloadScheduleFromCache();
  }

  Future<List<int>> reorderScheduleDay({
    required DateTime date,
    required List<Lesson> originalOrder,
    required List<Lesson> newOrder,
  }) async {
    final ids = await _scheduleRepository.reorderDayLessons(
      yearId: _selectedYearId,
      date: date,
      originalOrder: originalOrder,
      newOrder: newOrder,
    );
    if (ids.isNotEmpty) {
      await _reloadScheduleFromCache();
    }
    return ids;
  }

  Future<void> revertScheduleOverrides(Iterable<int> ids) async {
    await _scheduleRepository.revertOverrideIds(ids);
    await _reloadScheduleFromCache();
  }

  Future<void> revertScheduleOverride(int id) async {
    await _scheduleRepository.revertOverride(id);
    await _reloadScheduleFromCache();
  }

  Future<void> revertWeekOverrides() async {
    await _scheduleRepository.revertWeek(_selectedYearId, _weekStart);
    await _reloadScheduleFromCache();
  }

  Future<List<ScheduleOverride>> loadWeekOverrides() =>
      _scheduleRepository.loadWeekOverrides(_weekStart, _selectedYearId);

  Future<List<DaySchedule>> loadWeekRawLessons() =>
      _scheduleRepository.loadWeekRaw(_weekStart, _selectedYearId);

  // ── Смена недели/года ──────────────────────────────────────────────────

  Future<void> changeWeek(DateTime newMonday) async {
    final myToken = ++_weekToken;
    _weekStart = newMonday;
    _schedule = null;
    _marks = null;
    _scheduleUpdated = null;
    scheduleTick.value++;
    _notify();

    final cached = await _scheduleRepository.loadCached(
      newMonday,
      _selectedYearId,
    );
    if (myToken != _weekToken || _disposed) return;
    final updated = await _scheduleRepository.lastUpdated(
      newMonday,
      _selectedYearId,
    );
    if (myToken != _weekToken || _disposed) return;
    final cachedMarks = await _marksRepository.loadCached(
      _selectedYearId,
      newMonday,
    );
    if (myToken != _weekToken || _disposed) return;

    _schedule = cached;
    _scheduleUpdated = updated;
    _marks = cachedMarks.isEmpty ? null : cachedMarks;
    await _refreshOverridesMeta();
    if (myToken != _weekToken || _disposed) return;
    scheduleTick.value++;
    _notify();

    await refreshSchedule(silent: true);
  }

  Future<void> changeYear(int yearId) async {
    if (yearId == _selectedYearId) return;
    final myToken = ++_yearToken;
    _selectedYearId = yearId;
    _grades = null;
    _gradesUpdated = null;
    _homeworks = null;
    _homeworksUpdated = null;
    _teachers = null;
    _teachersUpdated = null;
    _attendances = null;
    gradesTick.value++;
    homeworksTick.value++;
    profileTick.value++;
    scheduleTick.value++;
    _notify();

    await _cache.saveInt(_selectedYearKey, yearId);
    if (myToken != _yearToken || _disposed) return;

    final cachedGrades = await _gradesRepository.loadCached(yearId);
    if (myToken != _yearToken || _disposed) return;
    final updatedGrades = await _gradesRepository.lastUpdated(yearId);
    if (myToken != _yearToken || _disposed) return;
    final cachedHw = await _homeworkRepository.loadCached(yearId);
    if (myToken != _yearToken || _disposed) return;
    final updatedHw = await _homeworkRepository.lastUpdated(yearId);
    if (myToken != _yearToken || _disposed) return;
    final cachedTeachers = await _teachersRepository.loadCached(yearId);
    if (myToken != _yearToken || _disposed) return;
    final updatedTeachers = await _teachersRepository.lastUpdated(yearId);
    if (myToken != _yearToken || _disposed) return;
    final cachedAtt = await _attendanceRepository.loadCached(yearId);
    if (myToken != _yearToken || _disposed) return;

    _grades = cachedGrades;
    _gradesUpdated = updatedGrades;
    _homeworks = cachedHw;
    _homeworksUpdated = updatedHw;
    _teachers = cachedTeachers;
    _teachersUpdated = updatedTeachers;
    _attendances = cachedAtt.isEmpty ? null : cachedAtt;
    gradesTick.value++;
    homeworksTick.value++;
    profileTick.value++;
    scheduleTick.value++;
    _notify();

    await _loadBells();
    if (myToken != _yearToken || _disposed) return;
    await refreshGrades(silent: true);
    if (myToken != _yearToken || _disposed) return;
    await refreshHomeworks(silent: true);
    if (myToken != _yearToken || _disposed) return;
    await _refreshTeachers();
    if (myToken != _yearToken || _disposed) return;
    await refreshAttendances(silent: true);
  }

  static DateTime _currentMonday() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }
}
