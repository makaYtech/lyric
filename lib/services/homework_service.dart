import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../models/homework.dart';
import 'auth_service.dart';

/// /core/api/student_homeworks — полные записи ДЗ по году.
/// Для расписания эта же ручка дёргается отдельно (StudentHomework),
/// там нужен только homework_id → текст. Здесь — весь объект.
class HomeworkService {
  final ApiClient _api;
  HomeworkService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Homework>> fetchHomeworks(
      EposTokens tokens, {
        required DateTime from,
        required DateTime to,
        required int academicYearId,
      }) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/student_homeworks'
          '?begin_date=${dotDate(from)}'
          '&end_date=${dotDate(to)}'
          '&academic_year_id=$academicYearId'
          '&student_profile_id=${tokens.profileId}'
          '&page=1'
          '&per_page=1000'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 3);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(Homework.fromJson)
        .toList();
  }
}