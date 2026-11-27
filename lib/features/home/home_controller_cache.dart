part of 'home_controller.dart';

extension HomeControllerCache on HomeController {
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

  /// Диагностика в логе: если activeProfileId пуст, а type=parent —
  /// выбранного ребёнка потеряли, запросы уйдут родительским pid.
  Future<void> _loadCachedAll() async {
    debugPrint('Сессия на входе: $debugProfileInfo');
    final profileFut = _profileRepository.loadCached();
    final profileUpdFut = _profileRepository.lastUpdated();
    final yearsFut = _yearsRepository.loadCached();
    final groupsFut = _groupsRepository.loadCached();
    final yearIdFut = _cache.loadInt(_selectedYearKey);
    final teacherIdsFut = _cache.loadString(_studentTeacherIdsKey);
    final ecGroupIdsFut = _cache.loadString(_ecGroupIdsKey);

    final profile = await profileFut;
    final profileUpdated = await profileUpdFut;
    final years = await yearsFut;
    final groups = await groupsFut;
    final savedYearId = await yearIdFut;
    final teacherIdsRaw = await teacherIdsFut;
    final ecGroupIdsRaw = await ecGroupIdsFut;

    if (teacherIdsRaw != null && teacherIdsRaw.isNotEmpty) {
      _studentTeacherIds = teacherIdsRaw
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
    }

    if (ecGroupIdsRaw != null && ecGroupIdsRaw.isNotEmpty) {
      _ecGroupIds = ecGroupIdsRaw
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toList();
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
}
