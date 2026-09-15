import 'package:flutter/foundation.dart';

import '../core/auth/epos_session.dart';
import '../core/auth/session_notifier.dart';
import '../core/auth/session_refresh_service.dart';
import '../core/backend/backends_prefs.dart';
import '../core/cache/cache_service.dart';
import '../core/settings/homework_prefs.dart';
import '../core/settings/schedule_prefs.dart';
import '../core/settings/teacher_prefs.dart';
import '../models/academic_year.dart';
import '../models/day_schedule.dart';
import '../models/homework.dart';
import '../models/mark.dart';
import '../models/student_profile.dart';
import '../models/subject_grade.dart';
import '../models/teacher.dart';
import '../repositories/academic_years_repository.dart';
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
    required EposSession session,
    required void Function(String message) onError,
    ProfileRepository? profileRepository,
    GradesRepository? gradesRepository,
    AcademicYearsRepository? yearsRepository,
    ScheduleRepository? scheduleRepository,
    StudentGroupsRepository? groupsRepository,
    MarksRepository? marksRepository,
    HomeworkRepository? homeworkRepository,
    TeachersRepository? teachersRepository,
    CacheService? cache,
  })  : _session = session,
        _onError = onError,
        _profileRepository = profileRepository ?? ProfileRepository(),
        _gradesRepository = gradesRepository ?? GradesRepository(),
        _yearsRepository = yearsRepository ?? AcademicYearsRepository(),
        _scheduleRepository = scheduleRepository ?? ScheduleRepository(),
        _groupsRepository = groupsRepository ?? StudentGroupsRepository(),
        _marksRepository = marksRepository ?? MarksRepository(),
        _homeworkRepository = homeworkRepository ?? HomeworkRepository(),
        _teachersRepository = teachersRepository ?? TeachersRepository(),
        _cache = cache ?? CacheService() {
    _weekStart = _currentMonday();
  }

  EposSession _session;
  // Актуальная сессия живёт в AuthCoordinator: он её обновляет молча,
  // прямо посреди запросов. Читаем оттуда, иначе после тихого re-auth
  // репозитории уйдут со старым, уже мёртвым authToken.
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
  final CacheService _cache;

  static const _selectedYearKey = 'selected_academic_year_id';
  static const _studentTeacherIdsKey = 'student_teacher_ids';
  static const _fallbackYearId = 14;

  static const titles = ['Профиль', 'Оценки', 'Расписание', 'ДЗ'];

  bool _disposed = false;

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

  List<Mark>? _marks;
  List<Mark>? get marks => _marks;

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
    await BackendPrefs.load();
    // Кэш — вещь опциональная. Если база не открылась или схема битая,
    // это не повод не идти в сеть: раньше исключение отсюда обрывало
    // init(), refreshAll() не вызывался, и все флаги загрузки навсегда
    // оставались true — экран висел в вечной загрузке без ошибок.
    try {
      await _loadCachedAll();
    } catch (e) {
      debugPrint('Кэш не загрузился: $e');
    }
    await refreshAll();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void setTabIndex(int i) {
    if (i == _tabIndex) return;
    _tabIndex = i;
    _notify();
  }

  Future<void> updateSession(EposSession session) async {
    _session = session;
    AuthCoordinator.instance.setSession(session);
    await SessionRefreshService.instance.save(session);
    SessionNotifier.instance.clear();
    _notify();
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

    final yearId =
        savedYearId ?? _currentYearIdFrom(years) ?? _fallbackYearId;

    final gradesFut = _gradesRepository.loadCached(yearId);
    final gradesUpdFut = _gradesRepository.lastUpdated(yearId);
    final scheduleFut = _scheduleRepository.loadCached(_weekStart, yearId);
    final scheduleUpdFut =
    _scheduleRepository.lastUpdated(_weekStart, yearId);
    final marksFut = _marksRepository.loadCached(yearId, _weekStart);
    final homeworksFut = _homeworkRepository.loadCached(yearId);
    final homeworksUpdFut = _homeworkRepository.lastUpdated(yearId);
    final teachersFut = _teachersRepository.loadCached(yearId);
    final teachersUpdFut = _teachersRepository.lastUpdated(yearId);

    final grades = await gradesFut;
    final gradesUpdated = await gradesUpdFut;
    final schedule = await scheduleFut;
    final scheduleUpdated = await scheduleUpdFut;
    final marks = await marksFut;
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
    _homeworks = homeworks;
    _homeworksUpdated = homeworksUpdated;
    _teachers = teachers;
    _teachersUpdated = teachersUpdated;
    _notify();
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
    required Future<void> Function() body,
    required String errorToast,
    required bool silent,
  }) async {
    setLoading(true);
    setError(null);
    _notify();

    Future<void> runBody() => body();

    try {
      await runBody();
    } on SessionExpiredException {
      // ApiClient уже попробовал обновиться сам и не смог — markExpired
      // там же и выставлен. Своей ошибки не рисуем: покажется шторка входа.
    } catch (e) {
      if (_disposed) return;
      setError('Не удалось обновить: $e');
      if (!silent) _onError(errorToast);
    } finally {
      if (!_disposed) {
        setLoading(false);
        _notify();
      }
    }
  }

  /// Годы — первыми и обязательно до остального: на чистой установке
  /// _selectedYearId равен фолбэку (14), и все запросы с ним уходят
  /// «в никуда», возвращая пустоту.
  Future<void> refreshAll() async {
    await _refreshYears();
    await Future.wait([
      refreshProfile(),
      refreshGrades(),
      refreshSchedule(),
      refreshHomeworks(),
      _refreshTeachers(),
    ]);
  }

  Future<void> refreshProfile({bool silent = false}) => _runRefresh(
    setLoading: (v) => _profileLoading = v,
    setError: (e) => _profileError = e,
    body: () async {
      final profile =
      await _profileRepository.refresh(tokens);
      final updated = await _profileRepository.lastUpdated();
      if (_disposed) return;
      _profile = profile;
      _profileUpdated = updated;
    },
    errorToast: 'Не удалось обновить профиль',
    silent: silent,
  );

  Future<void> _refreshTeachers() async {
    _teachersLoading = true;
    _notify();
    try {
      final list = await _teachersRepository.refresh(
        tokens,
        _selectedYearId,
      );
      final updated =
      await _teachersRepository.lastUpdated(_selectedYearId);
      if (_disposed) return;
      _teachers = list;
      _teachersUpdated = updated;
      _teachersError = null;
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
    } catch (e) {
      if (_disposed) return;
      _teachersError = 'Не удалось обновить: $e';
    } finally {
      if (!_disposed) {
        _teachersLoading = false;
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
    } catch (_) {
      // намеренно молча
    }
  }

  Future<void> refreshGrades({bool silent = false}) => _runRefresh(
    setLoading: (v) => _gradesLoading = v,
    setError: (e) => _gradesError = e,
    body: () async {
      final grades = await _gradesRepository.refresh(
        tokens,
        _selectedYearId,
      );
      final updated =
      await _gradesRepository.lastUpdated(_selectedYearId);
      if (_disposed) return;
      _grades = grades;
      _gradesUpdated = updated;
    },
    errorToast: 'Не удалось обновить оценки',
    silent: silent,
  );

  Future<void> _ensureGroups() async {
    if (_groupIds.isNotEmpty) return;
    try {
      final groups = await _groupsRepository.refresh(tokens);
      if (_disposed) return;
      _groupIds = groups.map((g) => g.id).toList();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
      rethrow;
    } catch (_) {
      // намеренно молча
    }
  }

  Future<void> refreshSchedule({bool silent = false}) => _runRefresh(
    setLoading: (v) => _scheduleLoading = v,
    setError: (e) => _scheduleError = e,
    body: () async {
      await _ensureGroups();
      if (_groupIds.isEmpty) {
        throw Exception('не удалось получить список групп ученика');
      }
      final monday = _weekStart;
      final sunday = monday.add(const Duration(days: 6));

      final results = await Future.wait<Object>([
        _scheduleRepository.refresh(
          tokens,
          monday,
          _selectedYearId,
          _groupIds,
        ),
        _marksRepository.refresh(
          tokens,
          _selectedYearId,
          from: monday,
          to: sunday,
        ),
      ]);
      final schedule = results[0] as List<DaySchedule>;
      final marks = results[1] as List<Mark>;

      final updated = await _scheduleRepository.lastUpdated(
        monday,
        _selectedYearId,
      );

      final newIds = <int>{..._studentTeacherIds};
      for (final day in schedule) {
        for (final l in day.lessons) {
          final tid = l.teacherId;
          if (tid != null) newIds.add(tid);
        }
      }
      if (newIds.length != _studentTeacherIds.length) {
        _studentTeacherIds = newIds;
        await _cache.saveString(
          _studentTeacherIdsKey,
          newIds.join(','),
        );
      }

      if (_disposed) return;
      _schedule = schedule;
      _marks = marks;
      _scheduleUpdated = updated;
    },
    errorToast: 'Не удалось обновить расписание',
    silent: silent,
  );

  Future<void> refreshHomeworks({bool silent = false}) => _runRefresh(
    setLoading: (v) => _homeworksLoading = v,
    setError: (e) => _homeworksError = e,
    body: () async {
      final range = _academicYearRange(DateTime.now());
      final homeworks = await _homeworkRepository.refresh(
        tokens,
        _selectedYearId,
        from: range.$1,
        to: range.$2,
      );
      final updated =
      await _homeworkRepository.lastUpdated(_selectedYearId);
      if (_disposed) return;
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

  // ── Смена недели/года ──────────────────────────────────────────────────

  Future<void> changeWeek(DateTime newMonday) async {
    _weekStart = newMonday;
    _schedule = null;
    _marks = null;
    _scheduleUpdated = null;
    _notify();

    final cached =
    await _scheduleRepository.loadCached(newMonday, _selectedYearId);
    final updated =
    await _scheduleRepository.lastUpdated(newMonday, _selectedYearId);
    final cachedMarks =
    await _marksRepository.loadCached(_selectedYearId, newMonday);
    if (_disposed) return;
    _schedule = cached;
    _scheduleUpdated = updated;
    _marks = cachedMarks.isEmpty ? null : cachedMarks;
    _notify();

    await refreshSchedule(silent: true);
  }

  Future<void> changeYear(int yearId) async {
    if (yearId == _selectedYearId) return;
    _selectedYearId = yearId;
    _grades = null;
    _gradesUpdated = null;
    _homeworks = null;
    _homeworksUpdated = null;
    _teachers = null;
    _teachersUpdated = null;
    _notify();

    await _cache.saveInt(_selectedYearKey, yearId);

    final cachedGrades = await _gradesRepository.loadCached(yearId);
    final updatedGrades = await _gradesRepository.lastUpdated(yearId);
    final cachedHw = await _homeworkRepository.loadCached(yearId);
    final updatedHw = await _homeworkRepository.lastUpdated(yearId);
    final cachedTeachers = await _teachersRepository.loadCached(yearId);
    final updatedTeachers = await _teachersRepository.lastUpdated(yearId);
    if (_disposed) return;
    _grades = cachedGrades;
    _gradesUpdated = updatedGrades;
    _homeworks = cachedHw;
    _homeworksUpdated = updatedHw;
    _teachers = cachedTeachers;
    _teachersUpdated = updatedTeachers;
    _notify();

    await refreshGrades(silent: true);
    await refreshHomeworks(silent: true);
    await _refreshTeachers();
  }

  static DateTime _currentMonday() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }
}