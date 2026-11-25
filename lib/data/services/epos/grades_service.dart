import '../../../core/network/api_client.dart';
import '../../../domain/grades/subject_grade.dart';
import './api_endpoints.dart';
import './auth_service.dart';

class GradesService {
  final ApiClient _api;

  GradesService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<SubjectGrade>> fetchGrades(
    EposTokens tokens, {
    required int academicYearId,
  }) => _api.getTyped(
    eposUri('/reports/api/progress/json', {
      'academic_year_id': academicYearId,
      'hide_half_years': true,
      'pid': tokens.profileId,
      'student_profile_id': tokens.profileId,
    }),
    tokens,
    attempts: 5,
    parse: SubjectGrade.fromApi,
  );
}
