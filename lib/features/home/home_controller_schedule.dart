part of 'home_controller.dart';

extension HomeControllerSchedule on HomeController {
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

  /// Обновляет расписание и в БД, и в памяти; здесь же обновляется годовой
  /// список ДЗ (нужен вкладке ДЗ и офлайн-пересборке). student_homeworks — один запрос.
  Future<void> refreshSchedule({bool silent = false}) {
    final myToken = ++_scheduleToken;
    return _runRefresh(
      setLoading: (v) {
        _scheduleLoading = v;
        _homeworksLoading = v;
      },
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
        final range = academicYearRange(DateTime.now());

        // Параллельно: EC-ДЗ (источник ec_group_ids), marks за неделю и
        // годовой список ДЗ (в БД, источник матчинга ДЗ к урокам).
        final parallel = await Future.wait<Object>([
          _ecHomeworkService.fetchEcHomeworks(
            tokens,
            from: monday,
            to: sunday,
            academicYearId: yearId,
          ),
          _marksRepository.refresh(tokens, yearId, from: monday, to: sunday),
          _homeworkRepository.refresh(
            tokens,
            yearId,
            from: range.$1,
            to: range.$2,
          ),
        ]);
        if (myToken != _scheduleToken || _disposed) return;
        if (yearId != _selectedYearId || monday != _weekStart) return;

        final ecHomeworks = parallel[0] as List<EcHomework>;
        final marks = parallel[1] as List<Mark>;
        final homeworks = parallel[2] as List<Homework>;

        final newEcGroups = <int>{
          for (final h in ecHomeworks)
            if (h.ecGroupId != null) h.ecGroupId!,
        };
        final groupsChanged =
            newEcGroups.isNotEmpty &&
            !_sameSet(newEcGroups, _ecGroupIds.toSet());
        if (groupsChanged) {
          _ecGroupIds = newEcGroups.toList();
          await _cache.saveString(_ecGroupIdsKey, _ecGroupIds.join(','));
        }

        // ДЗ передаём готовыми — сервис их не тянет.
        final schedule = await _scheduleRepository.refresh(
          tokens,
          monday,
          yearId,
          _groupIds,
          ecGroupIds: _ecGroupIds,
          classUnitIds: _classUnitIds,
          groupHomeworksByDue: HomeworkPrefs.groupByDue.value,
          allHomeworks: homeworks,
        );
        if (myToken != _scheduleToken || _disposed) return;
        if (yearId != _selectedYearId || monday != _weekStart) return;

        final updatedSchedule = await _scheduleRepository.lastUpdated(
          monday,
          yearId,
        );
        final updatedHomeworks = await _homeworkRepository.lastUpdated(yearId);
        if (myToken != _scheduleToken || _disposed) return;
        if (yearId != _selectedYearId || monday != _weekStart) return;

        // Пополняем set teacher_id для фильтра «только мои учителя».
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
        _homeworks = homeworks;
        _scheduleUpdated = updatedSchedule;
        _homeworksUpdated = updatedHomeworks;
        await _refreshOverridesMeta();
        if (myToken != _scheduleToken || _disposed) return;
        homeworksTick.value++;

        if (groupsChanged && _ecGroupIds.isNotEmpty) {
          unawaited(refreshSchedule(silent: true));
        }
      },
      errorToast: 'Не удалось обновить расписание',
      silent: silent,
    );
  }

  static bool _sameSet(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }
}
