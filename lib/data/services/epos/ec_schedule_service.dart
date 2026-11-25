import '../../../core/network/api_client.dart';
import '../../../core/util/date_time.dart';
import '../../../domain/schedule/ec_schedule_item.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// /ec/api/ec_schedule_items — расписание внеурочных занятий.
///
/// ec_group_ids собираются из ответа EcHomeworkService и хранятся
/// в prefs; class_unit_ids опционален.
class EcScheduleService {
  final ApiClient _api;
  EcScheduleService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<EcScheduleItem>> fetchEcItems(
    EposTokens tokens, {
    required DateTime from,
    required DateTime to,
    required int academicYearId,
    required List<int> ecGroupIds,
    List<int> classUnitIds = const [],
  }) async {
    if (ecGroupIds.isEmpty) return const [];

    return _api.getTyped(
      eposUri('/ec/api/ec_schedule_items', {
        'academic_year_id': academicYearId,
        'student_profile_ids': tokens.profileId,
        'begin_date': isoDate(from),
        'end_date': isoDate(to),
        'ec_group_ids': ecGroupIds.join(','),
        'pid': tokens.profileId,
        'class_unit_ids': classUnitIds.isEmpty ? null : classUnitIds.join(','),
      }),
      tokens,
      attempts: 2,
      silent: true,
      parse: EcScheduleItem.fromJson,
    );
  }
}
