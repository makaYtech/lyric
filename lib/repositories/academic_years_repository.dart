import '../core/cache/cache_service.dart';
import '../models/academic_year.dart';
import '../services/academic_years_service.dart';
import '../services/auth_service.dart';

class AcademicYearsRepository {
  final AcademicYearsService _service;
  final CacheService _cache;
  static const _cacheKey = 'academic_years';

  AcademicYearsRepository({AcademicYearsService? service, CacheService? cache})
      : _service = service ?? AcademicYearsService(),
        _cache = cache ?? CacheService();

  Future<List<AcademicYear>?> loadCached() async {
    final json = await _cache.loadList(_cacheKey);
    if (json == null) return null;
    try {
      return json
          .whereType<Map<String, dynamic>>()
          .map(AcademicYear.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<AcademicYear>> refresh(EposTokens tokens) async {
    final years = await _service.fetchYears(tokens);
    await _cache.saveList(
      _cacheKey,
      years.map((y) => y.toJson()).toList(),
    );
    return years;
  }
}