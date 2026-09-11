import '../core/cache/cache_service.dart';
import '../models/student_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';

class ProfileRepository {
  final ProfileService _service;
  final CacheService _cache;
  static const _cacheKey = 'profile';

  ProfileRepository({ProfileService? service, CacheService? cache})
      : _service = service ?? ProfileService(),
        _cache = cache ?? CacheService();

  Future<StudentProfile?> loadCached() async {
    final json = await _cache.load(_cacheKey);
    if (json == null) return null;
    return StudentProfile.fromJson(json);
  }

  Future<StudentProfile> refresh(EposTokens tokens) async {
    final profile = await _service.fetchProfile(tokens);
    await _cache.save(_cacheKey, profile.toJson());
    return profile;
  }

  Future<DateTime?> lastUpdated() => _cache.lastUpdated(_cacheKey);
}
