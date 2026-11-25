part of 'home_controller.dart';

extension HomeControllerOverrides on HomeController {
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
    _daysWithOverrides = overrides.map((o) => isoDate(o.date)).toSet();
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
    // EC-группы привязаны к году: соберутся заново из ec_student_homeworks.
    _ecGroupIds = const [];
    gradesTick.value++;
    homeworksTick.value++;
    profileTick.value++;
    scheduleTick.value++;
    _notify();

    await _cache.saveInt(_selectedYearKey, yearId);
    await _cache.saveString(_ecGroupIdsKey, '');
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
}
