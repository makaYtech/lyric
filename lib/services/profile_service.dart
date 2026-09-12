import 'dart:convert';
import '../core/network/epos_http_client.dart';
import '../models/student_profile.dart';
import 'auth_service.dart';
import 'api_endpoints.dart';
import 'epos_response_guard.dart';

class ProfileService {
  Future<StudentProfile> fetchProfile(EposTokens tokens) async {
    final client = await createEposHttpClient();
    try {
      final headers = {
        'Auth-Token': tokens.authToken,
        'Profile-Id': tokens.profileId,
        'Accept': 'application/json',
      };

      // 1. Профиль ученика
      final profileResp = await client.get(
        ApiEndpoints.studentProfile(tokens.profileId),
        headers: headers,
      );
      if (profileResp.statusCode != 200) {
        throw Exception(
          'student_profiles вернул ${profileResp.statusCode}: ${profileResp.body}',
        );
      }
      final decoded =
      jsonDecode(utf8.decode(profileResp.bodyBytes)) as Map<String, dynamic>;

      // 2. Узнаём user_id и запрашиваем школы
      final userId = decoded['user_id'];
      if (userId != null) {
        final userResp = await client.get(
          ApiEndpoints.users('$userId', tokens.profileId),
          headers: headers,
        );
        ensureSessionValid(userResp);
        if (userResp.statusCode == 200) {
          final userJson =
          jsonDecode(utf8.decode(userResp.bodyBytes)) as dynamic;

          // Достаём список profiles со school_shortname
          final profiles = _extractProfiles(userJson);

          // Подкладываем в decoded, чтобы fromJson их увидел
          decoded['profiles'] = profiles;
        }
      }

      return StudentProfile.fromJson(decoded);
    } finally {
      client.close();
    }
  }

  /// Достаём profiles[] из ответа acl/api/users.
  /// Ответ может быть List, Map с 'data' или Map с 'users'.
  List<dynamic> _extractProfiles(dynamic userJson) {
    dynamic root = userJson;

    if (root is Map<String, dynamic>) {
      root = root['data'] ?? root['users'] ?? root;
    }

    if (root is List) {
      // ids мог быть передан несколько раз — берём первый элемент,
      // либо собираем все profiles из всех пользователей.
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