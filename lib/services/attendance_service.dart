import '../core/network/api_client.dart';
import '../models/attendance.dart';
import 'api_endpoints.dart';
import 'auth_service.dart';

/// Отсутствия ученика за учебный год из /core/api/student_profiles.
/// Берём ту же ручку, что профиль, но с with_attendance=true и
/// academic_year_id — иначе поле attendances[] не приходит.
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
    final raw = decoded['attendances'] as List<dynamic>? ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Attendance.fromJson)
        .toList();
  }
}
