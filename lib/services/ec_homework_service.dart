import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../models/ec_homework.dart';
import 'auth_service.dart';

/// /ec/api/ec_student_homeworks — ДЗ внеурочных занятий.
///
/// Двойное назначение:
///   1) получить описания ДЗ для уроков внеурочки;
///   2) собрать ec_group_ids для EcScheduleService — сервер их отдаёт
///      в каждой записи (ec_group_id), а в student_profiles их нет.
class EcHomeworkService {
  final ApiClient _api;
  EcHomeworkService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<EcHomework>> fetchEcHomeworks(
    EposTokens tokens, {
    required DateTime from,
    required DateTime to,
    required int academicYearId,
  }) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/ec/api/ec_student_homeworks'
      '?begin_date=${dotDate(from)}'
      '&end_date=${dotDate(to)}'
      '&academic_year_id=$academicYearId'
      '&student_profile_id=${tokens.profileId}'
      '&page=1'
      '&per_page=50'
      '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 2, silent: true);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(EcHomework.fromJson)
        .toList();
  }
}
