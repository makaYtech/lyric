import '../../../core/network/api_client.dart';
import '../../../domain/people/account_context.dart';
import '../../../domain/people/student_profile.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// Профиль ученика + список школ из /acl/api/users.
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
        map['school_names'] = EposAccountContext.fromUsersResponse(userJson)
            .profiles
            .map((p) => p.schoolShortname)
            .whereType<String>()
            .toSet()
            .toList();
      } catch (_) {
        // Школы не критичны — профиль покажем и без них.
      }
    }

    return StudentProfile.fromJson(map);
  }
}
