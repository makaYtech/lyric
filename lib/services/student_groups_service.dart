import 'dart:convert';

import '../core/network/epos_http_client.dart';
import '../models/student_group.dart';
import 'api_endpoints.dart';
import 'auth_service.dart';
import 'epos_response_guard.dart';

/// Тянет группы ученика из /core/api/student_profiles/{id}.
/// Отдельный сервис, а не часть ProfileService: профиль и группы
/// нужны в разных местах, и незачем тащить весь профиль туда, где
/// нужны только id групп.
class StudentGroupsService {
  Future<List<StudentGroup>> fetchGroups(EposTokens tokens) async {
    final client = await createEposHttpClient();
    try {
      final resp = await client.get(
        ApiEndpoints.studentProfile(tokens.profileId),
        headers: {
          'Auth-Token': tokens.authToken,
          'Profile-Id': tokens.profileId,
          'Accept': 'application/json',
        },
      );
      ensureSessionValid(resp);
      if (resp.statusCode != 200) {
        throw Exception('student_profiles вернул ${resp.statusCode}');
      }
      final decoded =
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final rawGroups = decoded['groups'] as List<dynamic>? ?? const [];
      return rawGroups
          .whereType<Map<String, dynamic>>()
          .map(StudentGroup.fromJson)
          .toList();
    } finally {
      client.close();
    }
  }
}