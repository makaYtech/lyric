import '../../../core/network/api_client.dart';
import '../../../core/util/date_time.dart';
import '../../../domain/grades/mark.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// Оценки через /core/api/marks: каждая оценка отдельной записью
/// с created_at и schedule_lesson_id — это нужно расписанию.
class MarksService {
  final ApiClient _api;
  MarksService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Mark>> fetchMarks(
    EposTokens tokens, {
    required DateTime from,
    required DateTime to,
  }) => _api.getTyped(
    eposUri('/core/api/marks', {
      'student_profile_id': tokens.profileId,
      'created_at_from': dotDate(from),
      'created_at_to': dotDate(to),
      'page': 1,
      'per_page': 50,
      'pid': tokens.profileId,
    }),
    tokens,
    attempts: 3,
    parse: Mark.fromJson,
  );
}
