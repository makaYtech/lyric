import '../../../core/network/api_client.dart';
import '../../../core/util/date_time.dart';
import '../../../domain/homework/homework.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// /core/api/student_homeworks — полные записи ДЗ по году.
class HomeworkService {
  final ApiClient _api;
  HomeworkService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Homework>> fetchHomeworks(
    EposTokens tokens, {
    required DateTime from,
    required DateTime to,
    required int academicYearId,
  }) => _api.getTyped(
    eposUri('/core/api/student_homeworks', {
      'begin_date': dotDate(from),
      'end_date': dotDate(to),
      'academic_year_id': academicYearId,
      'student_profile_id': tokens.profileId,
      'page': 1,
      'per_page': 1000,
      'pid': tokens.profileId,
    }),
    tokens,
    attempts: 3,
    parse: Homework.fromJson,
  );
}
