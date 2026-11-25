part of 'home_controller.dart';

extension HomeControllerUpdates on HomeController {
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

    try {
      await body();
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

  /// Полный refresh. Годовой список ДЗ обновляется внутри refreshSchedule — он там нужен для сохранения в БД.
  Future<void> refreshAll() async {
    if (_refreshingAll) return;
    _refreshingAll = true;
    _notify();
    try {
      await _refreshYears();
      await Future.wait([
        refreshProfile(),
        refreshGrades(),
        refreshSchedule(),
        _refreshTeachers(),
        refreshAttendances(),
      ]);
    } finally {
      _refreshingAll = false;
      _notify();
    }
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

  /// Отсутствия обновляем только в refreshAll (ручка отдаёт весь год); при смене недели берём из кэша.
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
}
