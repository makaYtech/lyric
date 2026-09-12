import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../models/mark.dart';
import 'auth_service.dart';

/// Оценки через /core/api/marks.
/// В отличие от reports/api/progress/json, эта ручка отдаёт каждую оценку
/// отдельной записью с полем created_at и schedule_lesson_id — то, что нужно
/// расписанию, чтобы подсветить оценку именно на своём уроке.
class MarksService {
  final ApiClient _api;
  MarksService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Mark>> fetchMarks(
      EposTokens tokens, {
        required DateTime from,
        required DateTime to,
      }) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/marks'
          '?student_profile_id=${tokens.profileId}'
          '&created_at_from=${dotDate(from)}'
          '&created_at_to=${dotDate(to)}'
          '&page=1'
          '&per_page=50'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 3);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Mark.fromJson)
        .toList();
  }
}