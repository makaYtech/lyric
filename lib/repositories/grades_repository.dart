import '../core/cache/cache_service.dart';
import '../models/subject_grade.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';

/// Оценки кэшируются отдельно по каждому academicYearId — переключение
/// года в дропдауне сразу показывает то, что уже когда-то грузили,
/// без похода в сеть.
class GradesRepository {
  final GradesService _service;
  final CacheService _cache;

  GradesRepository({GradesService? service, CacheService? cache})
      : _service = service ?? GradesService(),
        _cache = cache ?? CacheService();

  String _key(int yearId) => 'grades_v2_$yearId';

  Future<List<SubjectGrade>?> loadCached(int yearId) async {
    final json = await _cache.loadList(_key(yearId));
    if (json == null) return null;
    return json
        .map((e) => SubjectGrade.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SubjectGrade>> refresh(EposTokens tokens, int yearId) async {
    final grades = await _service.fetchGrades(
      tokens,
      academicYearId: yearId,
    );
    await _cache.saveList(
      _key(yearId),
      grades.map((g) => g.toJson()).toList(),
    );
    return grades;
  }

  Future<DateTime?> lastUpdated(int yearId) => _cache.lastUpdated(_key(yearId));
}
