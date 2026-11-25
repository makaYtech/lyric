part of 'developer_screen.dart';

extension _DeveloperCacheTools on _DeveloperScreenState {
  Future<void> _clearProfileCache() async {
    await _run(_tools.clearProfileCache, successMessage: 'Кэш профиля сброшен');
  }

  Future<void> _clearYearsCache() async {
    await _run(
      _tools.clearAcademicYearsCache,
      successMessage: 'Кэш учебных годов сброшен',
    );
  }

  Future<void> _clearGroupsCache() async {
    await _run(
      _tools.clearStudentGroupsCache,
      successMessage: 'Кэш групп ученика сброшен',
    );
  }

  Future<void> _clearAvatars() async {
    final ok = await _confirm(
      title: 'Сбросить аватарки?',
      body:
          'Все локальные аватарки вернутся к инициалам. Файлы на '
          'устройстве не тронем — только ссылки в приложении.',
    );
    if (!ok) return;
    await _run(_tools.clearAvatarCache, successMessage: 'Аватарки сброшены');
  }

  Future<void> _resetDisplayPrefs() async {
    await _run(
      _tools.resetDisplayPrefs,
      successMessage: 'Настройки отображения сброшены',
    );
  }

  Future<void> _clearAllSharedPrefs() async {
    final ok = await _confirm(
      title: 'Снести все SharedPreferences?',
      body:
          'Кроме темы. Сюда попадают профиль, годы, группы, аватарки '
          'и все настройки. Кэш SQLite не тронем.',
    );
    if (!ok) return;
    await _run(
      _tools.clearAllSharedPrefs,
      successMessage: 'SharedPreferences очищены',
    );
  }

  Future<void> _clearLessons() async {
    await _run(_tools.clearLessons, successMessage: 'Расписание очищено');
  }

  Future<void> _clearGrades() async {
    await _run(
      _tools.clearGrades,
      successMessage: 'Оценки (включая историю) очищены',
    );
  }

  Future<void> _clearMarks() async {
    await _run(_tools.clearMarks, successMessage: 'Marks очищены');
  }

  Future<void> _clearAttendances() async {
    await _run(_tools.clearAttendances, successMessage: 'Отсутствия очищены');
  }

  Future<void> _clearHomeworks() async {
    await _run(_tools.clearHomeworks, successMessage: 'ДЗ очищены');
  }

  Future<void> _clearTeachers() async {
    await _run(_tools.clearTeachers, successMessage: 'Учителя очищены');
  }

  Future<void> _clearWholeDatabase() async {
    final ok = await _confirm(
      title: 'Снести всю SQLite?',
      body:
          'Расписание, оценки, marks, ДЗ, учителя — всё. '
          'SharedPreferences останутся.',
    );
    if (!ok) return;
    await _run(_tools.clearWholeDatabase, successMessage: 'SQLite очищена');
  }

  Future<void> _fullWipe() async {
    final ok = await _confirm(
      title: 'Полный сброс?',
      body:
          'Сессия, кэш, SharedPreferences и вся SQLite будут стёрты. '
          'device_key и тема оформления останутся. Приложение вернётся '
          'на LoginScreen.',
      confirmLabel: 'Снести ВСЁ',
    );
    if (!ok) return;
    await _run(
      _tools.fullWipe,
      successMessage: 'Полный сброс выполнен',
      afterAction: _goToLogin,
    );
  }
}
