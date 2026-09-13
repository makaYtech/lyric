import 'package:flutter/foundation.dart';

import '../core/auth/session_notifier.dart';
import '../core/cache/cache_service.dart';
import '../core/settings/schedule_prefs.dart';
import '../models/academic_year.dart';
import '../models/day_schedule.dart';
import '../models/homework.dart';
import '../models/mark.dart';
import '../models/student_profile.dart';
import '../models/subject_grade.dart';
import '../repositories/academic_years_repository.dart';
import '../repositories/grades_repository.dart';
import '../repositories/homework_repository.dart';
import '../repositories/marks_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/student_groups_repository.dart';
import '../services/auth_service.dart';
import '../services/session_expired_exception.dart';
import '../core/auth/token_storage.dart';
import '../core/settings/homework_prefs.dart';
import '../core/backend/backends_prefs.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required EposTokens tokens,
    required void Function(String message) onError,
    ProfileRepository? profileRepository,
    GradesRepository? gradesRepository,
    AcademicYearsRepository? yearsRepository,
    ScheduleRepository? scheduleRepository,
    StudentGroupsRepository? groupsRepository,
    MarksRepository? marksRepository,
    HomeworkRepository? homeworkRepository,
    CacheService? cache,
  })  : _tokens = tokens,
        _onError = onError,
        _profileRepository = profileRepository ?? ProfileRepository(),
        _gradesRepository = gradesRepository ?? GradesRepository(),
        _yearsRepository = yearsRepository ?? AcademicYearsRepository(),
        _scheduleRepository = scheduleRepository ?? ScheduleRepository(),
        _groupsRepository = groupsRepository ?? StudentGroupsRepository(),
        _marksRepository = marksRepository ?? MarksRepository(),
        _homeworkRepository = homeworkRepository ?? HomeworkRepository(),
        _cache = cache ?? CacheService() {
    _weekStart = _currentMonday();
  }

  EposTokens _tokens;
  EposTokens get tokens => _tokens;

  final void Function(String message) _onError;

  final ProfileRepository _profileRepository;
  final GradesRepository _gradesRepository;
  final AcademicYearsRepository _yearsRepository;
  final ScheduleRepository _scheduleRepository;
  final StudentGroupsRepository _groupsRepository;
  final MarksRepository _marksRepository;
  final HomeworkRepository _homeworkRepository;
  final CacheService _cache;
  final TokenStorage _tokenStorage = TokenStorage();

  static const _selectedYearKey = 'selected_academic_year_id';
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

  /// Оценки за текущую неделю — для точек на карточках уроков.
  /// Параллельно живут в SQLite (MarksDao), оффлайн подтягиваются оттуда.
  List<Mark>? _marks;
  List<Mark>? get marks => _marks;

  /// ДЗ за учебный год. В БД — целиком по году, в UI — группируется
  /// по датам. Оффлайн подтягивается из HomeworkDao.
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
      _homeworksLoading;

  String? get profileErrorForView => _profile == null ? _profileError : null;
  String? get gradesErrorForView =>
      (_grades == null || _grades!.isEmpty) ? _gradesError : null;
  String? get scheduleErrorForView =>
      (_schedule == null || _schedule!.isEmpty) ? _scheduleError : null;
  String? get homeworksErrorForView =>
      (_homeworks == null || _homeworks!.isEmpty) ? _homeworksError : null;

  // ── Жизненный цикл ─────────────────────────────────────────────────────

  Future<void> init() async {
    await _tokenStorage.save(_tokens);
    await SchedulePrefs.load();
    await HomeworkPrefs.load();
    await BackendPrefs.load();
    await _loadCachedAll();
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

  Future<void> updateTokens(EposTokens tokens) async {
    _tokens = tokens;
    await _tokenStorage.save(tokens);
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

    final profile = await profileFut;
    final profileUpdated = await profileUpdFut;
    final years = await yearsFut;
    final groups = await groupsFut;
    final savedYearId = await yearIdFut;

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

    final grades = await gradesFut;
    final gradesUpdated = await gradesUpdFut;
    final schedule = await scheduleFut;
    final scheduleUpdated = await scheduleUpdFut;
    final marks = await marksFut;
    final homeworks = await homeworksFut;
    final homeworksUpdated = await homeworksUpdFut;

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
    try {
      await body();
    } on SessionExpiredException {
      SessionNotifier.instance.markExpired();
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

  Future<void> refreshAll() => Future.wait([
    refreshProfile(),
    _refreshYears(),
    refreshGrades(),
    refreshSchedule(),
    refreshHomeworks(),
  ]);

  Future<void> refreshCurrentTab() {
    switch (_tabIndex) {
      case 0:
        return refreshProfile();
      case 1:
        return refreshGrades();
      case 2:
        return refreshSchedule();
      case 3:
        return refreshHomeworks();
      default:
        return Future.value();
    }
  }

  Future<void> refreshProfile({bool silent = false}) => _runRefresh(
    setLoading: (v) => _profileLoading = v,
    setError: (e) => _profileError = e,
    body: () async {
      final profile = await _profileRepository.refresh(_tokens);
      final updated = await _profileRepository.lastUpdated();
      if (_disposed) return;
      _profile = profile;
      _profileUpdated = updated;
    },
    errorToast: 'Не удалось обновить профиль',
    silent: silent,
  );

  Future<void> _refreshYears() async {
    try {
      final years = await _yearsRepository.refresh(_tokens);
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
      final grades =
      await _gradesRepository.refresh(_tokens, _selectedYearId);
      final updated = await _gradesRepository.lastUpdated(_selectedYearId);
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
      final groups = await _groupsRepository.refresh(_tokens);
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
          _tokens,
          monday,
          _selectedYearId,
          _groupIds,
        ),
        _marksRepository.refresh(
          _tokens,
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
        _tokens,
        _selectedYearId,
        from: range.$1,
        to: range.$2,
      );
      final updated = await _homeworkRepository.lastUpdated(_selectedYearId);
      if (_disposed) return;
      _homeworks = homeworks;
      _homeworksUpdated = updated;
    },
    errorToast: 'Не удалось обновить ДЗ',
    silent: silent,
  );

  /// Границы учебного года для запроса ДЗ: сентябрь текущего (или
  /// прошлого, если сейчас ещё лето) .. август следующего.
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
    _notify();

    await _cache.saveInt(_selectedYearKey, yearId);

    final cachedGrades = await _gradesRepository.loadCached(yearId);
    final updatedGrades = await _gradesRepository.lastUpdated(yearId);
    final cachedHw = await _homeworkRepository.loadCached(yearId);
    final updatedHw = await _homeworkRepository.lastUpdated(yearId);
    if (_disposed) return;
    _grades = cachedGrades;
    _gradesUpdated = updatedGrades;
    _homeworks = cachedHw;
    _homeworksUpdated = updatedHw;
    _notify();

    await refreshGrades(silent: true);
    await refreshHomeworks(silent: true);
  }

  static DateTime _currentMonday() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }
}