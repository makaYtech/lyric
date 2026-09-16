import 'dart:convert';

import '../core/network/api_client.dart';
import '../models/bells_timetable.dart';
import 'auth_service.dart';

/// /core/api/bells_timetables — расписание звонков школы.
class BellsService {
  final ApiClient _api;
  BellsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<({int id, String rawJson, BellsTimetable model})> fetch(
      EposTokens tokens, {
        required int timetableId,
        required int academicYearId,
      }) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/bells_timetables'
          '?ids=$timetableId'
          '&include=bells_day_timetables'
          '&academic_year_id=$academicYearId'
          '&pid=${tokens.profileId}',
    );

    final decoded = await _api.getRaw(uri, tokens, attempts: 3);
    if (decoded is! List || decoded.isEmpty) {
      throw Exception('bells_timetables вернул пустой ответ');
    }

    final first = decoded.first;
    if (first is! Map<String, dynamic>) {
      throw Exception('bells_timetables: неожиданный элемент массива');
    }

    return (
    id: first['id'] as int? ?? timetableId,
    rawJson: jsonEncode(first),
    model: BellsTimetable.fromJson(first),
    );
  }
}