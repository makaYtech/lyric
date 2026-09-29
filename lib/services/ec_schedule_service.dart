import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../models/ec_schedule_item.dart';
import 'auth_service.dart';

/// /ec/api/ec_schedule_items — расписание внеурочных занятий.
///
/// Требует ec_group_ids — их собираем из ответа EcHomeworkService
/// (там в каждой записи есть ec_group_id) и храним в prefs.
/// class_unit_ids опционален — если знаем, передаём.
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

    final parts = <String>[
      'academic_year_id=$academicYearId',
      'student_profile_ids=${tokens.profileId}',
      'begin_date=${isoDate(from)}',
      'end_date=${isoDate(to)}',
      'ec_group_ids=${ecGroupIds.join(',')}',
      'pid=${tokens.profileId}',
      if (classUnitIds.isNotEmpty) 'class_unit_ids=${classUnitIds.join(',')}',
    ];

    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/ec/api/ec_schedule_items'
      '?${parts.join('&')}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 2, silent: true);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(EcScheduleItem.fromJson)
        .toList();
  }
}
