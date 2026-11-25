import '../../../core/network/api_client.dart';
import '../../../domain/people/teacher.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// /core/api/teacher_profiles — список учителей школы.
///
/// Дополнительно тянем /core/api/rooms, чтобы определить «свои» кабинеты
/// учителя (responsible_id). Фильтр по responsible_id сервер игнорирует,
/// поэтому запрашиваем кабинеты batch-запросом и фильтруем на клиенте.
class TeachersService {
  final ApiClient _api;
  TeachersService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<Teacher>> fetchTeachers(
    EposTokens tokens, {
    required int academicYearId,
  }) async {
    // ВАЖНО: без silent. При ошибке сети репозиторий не дойдёт до saveAll,
    // и кэш учителей не снесётся.
    final teachers = await _api.getTyped(
      eposUri('/core/api/teacher_profiles', {
        'academic_year_id': academicYearId,
        'types': 'all',
        'page': 1,
        'per_page': 200,
        'pid': tokens.profileId,
      }),
      tokens,
      attempts: 2,
      parse: Teacher.fromJson,
    );
    if (teachers.isEmpty) return teachers;

    final allRoomIds = <int>{
      for (final t in teachers)
        for (final r in t.rooms) r.id,
    }.toList();
    if (allRoomIds.isEmpty) return teachers;

    final roomsRaw = await _api.getList(
      eposUri('/core/api/rooms', {
        'ids': allRoomIds.join(','),
        'all_schools': true,
        'pid': tokens.profileId,
      }),
      tokens,
      attempts: 2,
      silent: true,
    );

    // Если кабинеты не подтянулись (сеть/WAF), не портим ownedRoomIds.
    if (roomsRaw.isEmpty) return teachers;

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
