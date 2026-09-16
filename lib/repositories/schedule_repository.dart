import '../core/db/schedule_dao.dart';
import '../core/db/schedule_overrides_dao.dart';
import '../core/settings/schedule_prefs.dart';
import '../models/day_schedule.dart';
import '../models/lesson.dart';
import '../models/schedule_override.dart';
import '../services/auth_service.dart';
import '../services/schedule_service.dart';

class ScheduleRepository {
  final ScheduleService _service;
  final ScheduleDao _dao;
  final ScheduleOverridesDao _overridesDao;

  ScheduleRepository({
    ScheduleService? service,
    ScheduleDao? dao,
    ScheduleOverridesDao? overridesDao,
  })  : _service = service ?? ScheduleService(),
        _dao = dao ?? ScheduleDao(),
        _overridesDao = overridesDao ?? ScheduleOverridesDao();

  Future<List<DaySchedule>?> loadCached(
      DateTime weekStart,
      int academicYearId,
      ) async {
    final monday = _monday(weekStart);
    final days = await _dao.loadWeek(academicYearId, monday);
    final hasAny = days.any((d) => d.lessons.isNotEmpty);
    if (!hasAny) return null;

    final overrides = SchedulePrefs.showOverrides.value
        ? await _overridesDao.loadWeek(academicYearId, monday)
        : const <ScheduleOverride>[];
    return applyScheduleOverrides(days, overrides);
  }

  Future<List<DaySchedule>> refresh(
      EposTokens tokens,
      DateTime weekStart,
      int academicYearId,
      List<int> groupIds,
      ) async {
    final monday = _monday(weekStart);
    final days = await _service.fetchSchedule(
      tokens,
      weekStart: weekStart,
      academicYearId: academicYearId,
      groupIds: groupIds,
    );
    await _dao.saveWeek(academicYearId, days);

    final overrides = SchedulePrefs.showOverrides.value
        ? await _overridesDao.loadWeek(academicYearId, monday)
        : const <ScheduleOverride>[];
    return applyScheduleOverrides(days, overrides);
  }

  Future<DateTime?> lastUpdated(DateTime weekStart, int academicYearId) =>
      _dao.lastUpdated(academicYearId, _monday(weekStart));

  Future<List<DaySchedule>> loadWeekRaw(
      DateTime weekStart,
      int academicYearId,
      ) =>
      _dao.loadWeek(academicYearId, _monday(weekStart));

  Future<Lesson?> loadRawLessonById(
      int yearId,
      DateTime weekStart,
      int lessonId,
      ) async {
    final days = await _dao.loadWeek(yearId, _monday(weekStart));
    for (final d in days) {
      for (final l in d.lessons) {
        if (l.id == lessonId) return l;
        if (l.secondaryId == lessonId) return l;
      }
    }
    return null;
  }

  ScheduleOverridesDao get overrides => _overridesDao;

  Future<List<ScheduleOverride>> loadWeekOverrides(
      DateTime weekStart,
      int academicYearId,
      ) =>
      _overridesDao.loadWeek(academicYearId, _monday(weekStart));

  Future<Set<String>> loadDaysWithOverrides(
      DateTime weekStart,
      int academicYearId,
      ) async {
    final list = await loadWeekOverrides(weekStart, academicYearId);
    return list.map((o) => _isoDate(o.date)).toSet();
  }

  Future<List<int>> markDeletedMany({
    required int yearId,
    required DateTime date,
    required Iterable<int> lessonIds,
  }) {
    final list = lessonIds
        .map((id) => ScheduleOverride.delete(
      yearId: yearId,
      date: date,
      lessonId: id,
    ))
        .toList();
    return _overridesDao.insertAll(list);
  }

  Future<void> moveLesson({
    required int yearId,
    required DateTime date,
    required int lessonId,
    required String newStartTime,
    required String newEndTime,
  }) =>
      _overridesDao.insert(ScheduleOverride.move(
        yearId: yearId,
        date: date,
        lessonId: lessonId,
        startTime: newStartTime,
        endTime: newEndTime,
      ));

  /// Пакетная замена времени для нескольких уроков дня. Используется
  /// при drop на окно: одиночный урок = одна запись, пара = две.
  Future<List<int>> moveLessons({
    required int yearId,
    required DateTime date,
    required List<({int lessonId, String startTime, String endTime})> moves,
  }) {
    if (moves.isEmpty) return Future.value(const []);
    final list = moves
        .map((m) => ScheduleOverride.move(
      yearId: yearId,
      date: date,
      lessonId: m.lessonId,
      startTime: m.startTime,
      endTime: m.endTime,
    ))
        .toList();
    return _overridesDao.insertAll(list);
  }

  Future<List<int>> swapLessons({
    required int yearId,
    required DateTime date,
    required int lessonAId,
    required String lessonAStart,
    required String lessonAEnd,
    required int lessonBId,
    required String lessonBStart,
    required String lessonBEnd,
  }) {
    return _overridesDao.insertAll([
      ScheduleOverride.move(
        yearId: yearId,
        date: date,
        lessonId: lessonAId,
        startTime: lessonBStart,
        endTime: lessonBEnd,
      ),
      ScheduleOverride.move(
        yearId: yearId,
        date: date,
        lessonId: lessonBId,
        startTime: lessonAStart,
        endTime: lessonAEnd,
      ),
    ]);
  }

  Future<void> breakPair({
    required int yearId,
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) =>
      _overridesDao.insert(ScheduleOverride.pairBreak(
        yearId: yearId,
        date: date,
        primaryId: primaryId,
        secondaryId: secondaryId,
      ));

  Future<void> makePair({
    required int yearId,
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) async {
    await _overridesDao.deleteForLesson(yearId, date, primaryId);
    await _overridesDao.deleteForLesson(yearId, date, secondaryId);
    await _overridesDao.insert(ScheduleOverride.pairMake(
      yearId: yearId,
      date: date,
      primaryId: primaryId,
      secondaryId: secondaryId,
    ));
  }

  /// Перестановка уроков дня. Один reorder-override на день, предыдущий
  /// удаляется — так не копится мусор от промежуточных перетаскиваний.
  Future<List<int>> reorderDayLessons({
    required int yearId,
    required DateTime date,
    required List<Lesson> originalOrder,
    required List<Lesson> newOrder,
  }) async {
    if (newOrder.isEmpty) return const [];

    var same = true;
    for (var i = 0; i < newOrder.length; i++) {
      if (newOrder[i].id != originalOrder[i].id) {
        same = false;
        break;
      }
    }

    await _overridesDao.deleteReordersForDay(yearId, date);
    if (same) return const [];

    final order = newOrder
        .map((l) => l.id)
        .whereType<int>()
        .toList();
    if (order.isEmpty) return const [];

    final id = await _overridesDao.insert(ScheduleOverride.reorder(
      yearId: yearId,
      date: date,
      order: order,
    ));
    return [id];
  }

  Future<void> revertOverrideIds(Iterable<int> ids) =>
      _overridesDao.deleteByIds(ids);

  Future<void> revertOverride(int id) => _overridesDao.deleteById(id);

  Future<void> revertLesson(int yearId, DateTime date, int lessonId) =>
      _overridesDao.deleteForLesson(yearId, date, lessonId);

  Future<void> revertDay(int yearId, DateTime date) =>
      _overridesDao.deleteDay(yearId, date);

  Future<void> revertWeek(int yearId, DateTime weekStart) =>
      _overridesDao.deleteWeek(yearId, _monday(weekStart));

  DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
}