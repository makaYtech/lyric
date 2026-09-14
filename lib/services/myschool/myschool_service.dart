import '../../models/myschool/myschool_homework.dart';
import 'interval_helper.dart';
import 'myschool_api_client.dart';
import 'myschool_tokens.dart';

/// Тонкая обёртка над datamart для конкретных вещей. Сейчас — только ДЗ.
class MySchoolService {
  final MySchoolApiClient _api;
  MySchoolService({MySchoolApiClient? api}) : _api = api ?? MySchoolApiClient();

  /// ДЗ за [weeks] недель (включая текущую).
  Future<List<MySchoolHomework>> fetchHomeworks(
      MySchoolTokens tokens, {
        int weeks = 4,
      }) async {
    final intervals = IntervalHelper.lastWeeks(weeks);
    final requests = intervals
        .map((id) => {
      'interval_id': id,
      'obj_type': 'student_homeworks_materials',
      'student_id': tokens.studentId,
    })
        .toList();

    final responses = await _api.datamart(tokens, requests);

    final result = <MySchoolHomework>[];
    for (final r in responses.whereType<Map<String, dynamic>>()) {
      final data = r['data'] as List<dynamic>? ?? const [];
      for (final hw in data.whereType<Map<String, dynamic>>()) {
        final model = MySchoolHomework.fromJson(hw);
        if (model.isEmpty) continue; // «не задано» — не показываем
        result.add(model);
      }
    }
    // Сортируем по дате группировки — свежие снизу/сверху, на твой вкус.
    result.sort((a, b) {
      final ad = a.date, bd = b.date;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return result;
  }
}