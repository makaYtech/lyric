import '../core/network/api_client.dart';
import '../models/student_group.dart';
import 'api_endpoints.dart';
import 'auth_service.dart';

/// Тянет группы ученика из /core/api/student_profiles/{id}.
class StudentGroupsService {
  final ApiClient _api;
  StudentGroupsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<StudentGroup>> fetchGroups(EposTokens tokens) async {
    final decoded = await _api.get(
      ApiEndpoints.studentProfile(tokens.profileId),
      tokens,
      attempts: 2,
    );
    final rawGroups = decoded['groups'] as List<dynamic>? ?? const [];
    return rawGroups
        .whereType<Map<String, dynamic>>()
        .map(StudentGroup.fromJson)
        .toList();
  }
}