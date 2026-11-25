import '../../../core/network/api_client.dart';
import '../../../core/util/date_time.dart';
import '../../../domain/homework/ec_homework.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// /ec/api/ec_student_homeworks — ДЗ внеурочных занятий.
///
/// Нужен и для описаний ДЗ, и для сбора ec_group_ids: сервер отдаёт
/// ec_group_id в каждой записи, а в student_profiles его нет.
class EcHomeworkService {
  final ApiClient _api;
  EcHomeworkService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<EcHomework>> fetchEcHomeworks(
    EposTokens tokens, {
    required DateTime from,
    required DateTime to,
    required int academicYearId,
  }) => _api.getTyped(
    eposUri('/ec/api/ec_student_homeworks', {
      'begin_date': dotDate(from),
      'end_date': dotDate(to),
      'academic_year_id': academicYearId,
      'student_profile_id': tokens.profileId,
      'page': 1,
      'per_page': 50,
      'pid': tokens.profileId,
    }),
    tokens,
    attempts: 2,
    silent: true,
    parse: EcHomework.fromJson,
  );
}
