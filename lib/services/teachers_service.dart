import '../core/network/api_client.dart';
import '../models/teacher.dart';
import 'auth_service.dart';

/// /core/api/teacher_profiles — список учителей школы.
///
/// Дополнительно тянем /core/api/rooms, чтобы определить «свои»
/// кабинеты учителя (те, где он responsible_id). Фильтр по responsible_id
/// сервер игнорирует, поэтому запрашиваем все кабинеты учителей одним
/// batch-запросом и фильтруем клиент-сайдом.
class TeachersService {
  final ApiClient _api;
  TeachersService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Teacher>> fetchTeachers(
      EposTokens tokens, {
        required int academicYearId,
      }) async {
    final teachersUri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/teacher_profiles'
          '?academic_year_id=$academicYearId'
          '&types=all'
          '&page=1'
          '&per_page=200'
          '&pid=${tokens.profileId}',
    );
    final teachersRaw =
    await _api.getList(teachersUri, tokens, attempts: 2, silent: true);
    final teachers = teachersRaw
        .whereType<Map<String, dynamic>>()
        .map(Teacher.fromJson)
        .toList();
    if (teachers.isEmpty) return teachers;

    final allRoomIds = <int>{
      for (final t in teachers)
        for (final r in t.rooms) r.id,
    }.toList();
    if (allRoomIds.isEmpty) return teachers;

    final roomsUri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/rooms'
          '?ids=${allRoomIds.join(',')}'
          '&all_schools=true'
          '&pid=${tokens.profileId}',
    );
    final roomsRaw =
    await _api.getList(roomsUri, tokens, attempts: 2, silent: true);

    final requested = allRoomIds.toSet();
    final responsibleByRoom = <int, int?>{};
    for (final raw in roomsRaw.whereType<Map<String, dynamic>>()) {
      final id = raw['id'] as int?;
      if (id == null || !requested.contains(id)) continue;
      responsibleByRoom[id] = raw['responsible_id'] as int?;
    }

    return teachers.map((t) {
      final owned = <int>{
        for (final r in t.rooms)
          if (responsibleByRoom[r.id] == t.id) r.id,
      };
      return t.copyWith(ownedRoomIds: owned);
    }).toList();
  }
}