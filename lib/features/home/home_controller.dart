import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/auth/auth_coordinator.dart';
import '../../core/auth/epos_session.dart';
import '../../core/auth/session_notifier.dart';
import '../../core/auth/session_refresh_service.dart';
import '../../core/cache/cache_service.dart';
import '../../core/settings/homework_prefs.dart';
import '../../core/settings/schedule_prefs.dart';
import '../../core/settings/teacher_prefs.dart';
import '../../core/util/date_time.dart';
import '../../domain/common/academic_year.dart';
import '../../domain/attendance/attendance.dart';
import '../../domain/schedule/bells_timetable.dart';
import '../../domain/schedule/day_schedule.dart';
import '../../domain/homework/ec_homework.dart';
import '../../domain/homework/homework.dart';
import '../../domain/schedule/lesson.dart';
import '../../domain/grades/mark.dart';
import '../../domain/schedule/schedule_override.dart';
import '../../domain/people/student_profile.dart';
import '../../domain/grades/subject_grade.dart';
import '../../domain/people/teacher.dart';
import '../../data/repositories/academic_years_repository.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../data/repositories/bells_repository.dart';
import '../../data/repositories/grades_repository.dart';
import '../../data/repositories/homework_repository.dart';
import '../../data/repositories/marks_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../data/repositories/student_groups_repository.dart';
import '../../data/repositories/teachers_repository.dart';
import '../../data/services/epos/auth_service.dart';
import '../../data/services/epos/ec_homework_service.dart';
import '../../data/services/epos/session_expired_exception.dart';

part './home_controller_cache.dart';
part './home_controller_homework.dart';
part './home_controller_overrides.dart';
part './home_controller_schedule.dart';
part './home_controller_updates.dart';

const _selectedYearKey = 'selected_academic_year_id';
const _studentTeacherIdsKey = 'student_teacher_ids';
const _ecGroupIdsKey = 'ec_group_ids';
const _fallbackYearId = 14;
const _bellsTimetableIdFallback = 124412;

class HomeController extends ChangeNotifier {
  HomeController({
    required this._session,
    required this._onError,
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
    EcHomeworkService? ecHomeworkService,
  }) : _profileRepository = profileRepository ?? ProfileRepository(),
       _gradesRepository = gradesRepository ?? GradesRepository(),
       _yearsRepository = yearsRepository ?? AcademicYearsRepository(),
       _scheduleRepository = scheduleRepository ?? ScheduleRepository(),
       _groupsRepository = groupsRepository ?? StudentGroupsRepository(),
       _marksRepository = marksRepository ?? MarksRepository(),
       _homeworkRepository = homeworkRepository ?? HomeworkRepository(),
       _teachersRepository = teachersRepository ?? TeachersRepository(),
       _bellsRepository = bellsRepository ?? BellsRepository(),
       _attendanceRepository = attendanceRepository ?? AttendanceRepository(),
       _ecHomeworkService = ecHomeworkService ?? EcHomeworkService(),
       _cache = cache ?? CacheService() {
    _weekStart = currentMonday();
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
  final EcHomeworkService _ecHomeworkService;
  final CacheService _cache;

  static const titles = ['Профиль', 'Оценки', 'Расписание', 'ДЗ'];

  bool _disposed = false;

  /// Токены отмены: инкрементируются при новом запуске операции того же типа,
  /// каждый await сверяет свой токен, чтобы не затереть поля устаревшими данными.
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

  /// Спиннер всей операции «Обновить всё»: включается синхронно в момент тапа, иначе на плохой сети кнопка «молчит» до запуска _refreshYears.
  bool _refreshingAll = false;
  bool get refreshingAll => _refreshingAll;

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

  /// id внеурочных EC-групп: в student_profiles их нет, собираются из ответа
  /// /ec/api/ec_student_homeworks; пусто — EC-расписание не запрашивается.
  List<int> _ecGroupIds = const [];
  List<int> get ecGroupIds => _ecGroupIds;

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
  String? get homeworksError => _homeworksError;
  String? _homeworksError;

  late DateTime _weekStart;
  DateTime get weekStart => _weekStart;

  /// true — расписание уже один раз проскроллилось на текущий день в этом сеансе; сбрасывается при холодном старте.
  bool _scheduleAutoScrolledOnce = false;
  bool get scheduleAutoScrolledOnce => _scheduleAutoScrolledOnce;

  /// id класса для /ec/api/ec_schedule_items; берётся из профиля, до его загрузки пусто.
  List<int> get _classUnitIds {
    final id = _profile?.classUnitId;
    return id == null ? const [] : [id];
  }

  void markScheduleAutoScrolled() {
    if (_scheduleAutoScrolledOnce) return;
    _scheduleAutoScrolledOnce = true;
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
      _refreshingAll ||
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

  Future<void> init() async {
    await SchedulePrefs.load();
    await HomeworkPrefs.load();
    await TeacherPrefs.load();
    SchedulePrefs.showOverrides.addListener(_onShowOverridesChanged);
    HomeworkPrefs.groupByDue.addListener(_onGroupByDueChanged);

    try {
      await _loadCachedAll();
    } catch (e) {
      debugPrint('Кэш не загрузился: $e');
    }
    await _ensureSessionComplete();
    await _loadBells();
    await refreshAll();
  }

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
    _weekToken++;
    _yearToken++;
    _bellsToken++;
    _scheduleToken++;
    SchedulePrefs.showOverrides.removeListener(_onShowOverridesChanged);
    HomeworkPrefs.groupByDue.removeListener(_onGroupByDueChanged);
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
}
