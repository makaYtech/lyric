import '../core/db/attendance_dao.dart';
import '../models/attendance.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';

class AttendanceRepository {
  final AttendanceService _service;
  final AttendanceDao _dao;

  AttendanceRepository({AttendanceService? service, AttendanceDao? dao})
    : _service = service ?? AttendanceService(),
      _dao = dao ?? AttendanceDao();

  Future<List<Attendance>> refresh(EposTokens tokens, int yearId) async {
    final list = await _service.fetchAttendances(
      tokens,
      academicYearId: yearId,
    );
    await _dao.saveAll(yearId, list);
    return list;
  }

  Future<List<Attendance>> loadCached(int yearId) => _dao.loadAll(yearId);

  Future<DateTime?> lastUpdated(int yearId) => _dao.lastUpdated(yearId);
}
