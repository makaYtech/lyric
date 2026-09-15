import '../core/network/api_client.dart';
import '../models/student_profile.dart';
import 'api_endpoints.dart';
import 'auth_service.dart';

/// Профиль ученика + список школ из /acl/api/users.
/// Ходит через ApiClient — значит получает автоматический re-auth на 401.
class ProfileService {
  final ApiClient _api;
  ProfileService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<StudentProfile> fetchProfile(EposTokens tokens) async {
    final decoded = await _api.get(
      ApiEndpoints.studentProfile(tokens.profileId),
      tokens,
      attempts: 3,
    );
    if (decoded.isEmpty) {
      throw Exception('student_profiles вернул пустой ответ');
    }

    final map = Map<String, dynamic>.from(decoded);

    final userId = map['user_id'];
    if (userId != null) {
      try {
        final userJson = await _api.getRaw(
          ApiEndpoints.users('$userId', tokens.profileId),
          tokens,
          attempts: 1,
        );
        map['profiles'] = _extractProfiles(userJson);
      } catch (_) {
        // Школы — не критично, профиль покажем и без них.
      }
    }

    return StudentProfile.fromJson(map);
  }

  /// Достаём profiles[] из ответа acl/api/users.
  /// Ответ может быть List, Map с 'data' или Map с 'users'.
  List<dynamic> _extractProfiles(dynamic userJson) {
    dynamic root = userJson;

    if (root is Map<String, dynamic>) {
      root = root['data'] ?? root['users'] ?? root;
    }

    if (root is List) {
      final all = <dynamic>[];
      for (final user in root) {
        if (user is Map<String, dynamic>) {
          final profiles = user['profiles'];
          if (profiles is List) all.addAll(profiles);
        }
      }
      return all;
    }

    return const [];
  }
}