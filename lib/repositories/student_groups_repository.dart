import '../core/cache/cache_service.dart';
import '../models/student_group.dart';
import '../services/auth_service.dart';
import '../services/student_groups_service.dart';

/// Группы — статика: меняются раз в семестр, у ученика их 10–20 штук.
/// Поэтому храним в SharedPreferences (CacheService), а не в SQLite.
class StudentGroupsRepository {
  final StudentGroupsService _service;
  final CacheService _cache;
  static const _cacheKey = 'student_groups';

  StudentGroupsRepository({
    StudentGroupsService? service,
    CacheService? cache,
  })  : _service = service ?? StudentGroupsService(),
        _cache = cache ?? CacheService();

  Future<List<StudentGroup>?> loadCached() async {
    final json = await _cache.loadList(_cacheKey);
    if (json == null) return null;
    try {
      return json
          .whereType<Map<String, dynamic>>()
          .map(StudentGroup.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<StudentGroup>> refresh(EposTokens tokens) async {
    final groups = await _service.fetchGroups(tokens);
    await _cache.saveList(
      _cacheKey,
      groups.map((g) => g.toJson()).toList(),
    );
    return groups;
  }
}