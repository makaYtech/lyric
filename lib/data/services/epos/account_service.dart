import '../../../core/network/api_client.dart';
import '../../../domain/people/account_context.dart';
import '../../../domain/people/student_profile.dart';
import './api_endpoints.dart';
import './auth_service.dart';

/// Роль аккаунта (ученик/родитель) и профили детей.
class AccountService {
  final ApiClient _api;

  AccountService({ApiClient? api}) : _api = api ?? ApiClient();

  /// `/acl/api/users?ids=<user_id>&pid=<login profile>`.
  ///
  /// ids — user_id владельца аккаунта. В ручном входе его в сессии нет,
  /// поэтому fallback на profileId. Настоящий user_id приходит в ответе.
  Future<EposAccountContext> fetch(EposTokens tokens) async {
    final ids = tokens.userId?.toString() ?? tokens.profileId;
    final raw = await _api.getRaw(
      ApiEndpoints.users(ids, tokens.profileId),
      tokens,
      attempts: 2,
    );
    return EposAccountContext.fromUsersResponse(raw);
  }

  /// Профиль ребёнка — тот же student_profiles, но с pid ребёнка.
  Future<StudentProfile?> fetchChildProfile(
    EposTokens tokens,
    int childProfileId,
  ) async {
    final decoded = await _api.get(
      ApiEndpoints.studentProfile('$childProfileId'),
      tokens.withProfile('$childProfileId'),
      attempts: 2,
    );
    if (decoded.isEmpty) return null;
    return StudentProfile.fromJson(decoded);
  }
}
