import '../core/db/schedule_dao.dart';
import '../models/day_schedule.dart';
import '../services/auth_service.dart';
import '../services/schedule_service.dart';

class ScheduleRepository {
  final ScheduleService _service;
  final ScheduleDao _dao;

  ScheduleRepository({ScheduleService? service, ScheduleDao? dao})
      : _service = service ?? ScheduleService(),
        _dao = dao ?? ScheduleDao();

  Future<List<DaySchedule>?> loadCached(
      DateTime weekStart,
      int academicYearId,
      ) async {
    final days = await _dao.loadWeek(academicYearId, _monday(weekStart));
    final hasAny = days.any((d) => d.lessons.isNotEmpty);
    return hasAny ? days : null;
  }

  Future<List<DaySchedule>> refresh(
      EposTokens tokens,
      DateTime weekStart,
      int academicYearId,
      List<int> groupIds,
      ) async {
    final days = await _service.fetchSchedule(
      tokens,
      weekStart: weekStart,
      academicYearId: academicYearId,
      groupIds: groupIds,
    );
    await _dao.saveWeek(academicYearId, days);
    return days;
  }

  Future<DateTime?> lastUpdated(DateTime weekStart, int academicYearId) =>
      _dao.lastUpdated(academicYearId, _monday(weekStart));

  DateTime _monday(DateTime d) => DateTime(d.year, d.month, d.day);
}