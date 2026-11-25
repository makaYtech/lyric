part of 'home_controller.dart';

extension HomeControllerHomework on HomeController {
  /// Переключение группировки ДЗ: без сети, пересборка блока ДЗ из сохранённого годового списка в БД.
  void _onGroupByDueChanged() {
    unawaited(_regroupScheduleFromCache());
  }

  Future<void> _regroupScheduleFromCache() async {
    if (_disposed) return;
    try {
      final regrouped = await _scheduleRepository.regroupFromCache(
        _weekStart,
        _selectedYearId,
        HomeworkPrefs.groupByDue.value,
      );
      if (_disposed) return;
      _schedule = regrouped;
      scheduleTick.value++;
      _notify();
    } catch (e) {
      debugPrint('regroup из кэша упал: $e');
    }
  }

  /// Ручное обновление ДЗ (кнопка на вкладке ДЗ и смена года): весь учебный год в БД.
  Future<void> refreshHomeworks({bool silent = false}) => _runRefresh(
    setLoading: (v) => _homeworksLoading = v,
    setError: (e) => _homeworksError = e,
    revision: homeworksTick,
    body: () async {
      final yearId = _selectedYearId;
      final range = academicYearRange(DateTime.now());
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
}
