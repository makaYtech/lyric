import '../../../core/network/api_client.dart';
import '../../../core/util/json.dart';
import '../../../domain/attendance/attendance.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// Отсутствия ученика за учебный год из /core/api/student_profiles.
/// Без with_attendance=true и academic_year_id поле attendances[] не приходит.
class AttendanceService {
  final ApiClient _api;
  AttendanceService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Attendance>> fetchAttendances(
    EposTokens tokens, {
    required int academicYearId,
  }) async {
    final decoded = await _api.get(
      ApiEndpoints.studentProfileWithAttendance(
        tokens.profileId,
        academicYearId,
      ),
      tokens,
      attempts: 3,
    );
    return decoded.mapList('attendances').map(Attendance.fromJson).toList();
  }
}
