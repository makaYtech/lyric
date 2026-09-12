import '../core/network/api_client.dart';
import '../models/subject_grade.dart';
import 'auth_service.dart';

class GradesService {
  final ApiClient _api;

  GradesService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<SubjectGrade>> fetchGrades(
      EposTokens tokens, {
        required int academicYearId,
      }) async {
    final url = Uri.parse(
      'https://edu-epos.permkrai.ru/reports/api/progress/json'
          '?academic_year_id=$academicYearId'
          '&hide_half_years=true'
          '&pid=${tokens.profileId}'
          '&student_profile_id=${tokens.profileId}',
    );
    final decoded = await _api.getList(url, tokens, attempts: 5);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SubjectGrade.fromApi)
        .toList();
  }
}