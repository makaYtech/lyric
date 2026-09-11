import 'dart:convert';
import '../core/network/epos_http_client.dart';
import '../models/subject_grade.dart';
import 'auth_service.dart';

class GradesService {
  Future<List<SubjectGrade>> fetchGrades(
      EposTokens tokens, {
        required int academicYearId,
      }) async {
    final url = Uri.parse(
      'https://edu-epos.permkrai.ru/reports/api/progress/json'
          '?academic_year_id=$academicYearId'
          '&hide_half_years=true'
          '&pid=${tokens.profileId}'
          '&student_profile_id=${tokens.profileId}',
    );

    final client = await createEposHttpClient();
    try {
      final response = await client.get(
        url,
        headers: {
          'Auth-Token': tokens.authToken,
          'Profile-Id': tokens.profileId,
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'reports/progress вернул ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SubjectGrade.fromJson)
          .toList();
    } finally {
      client.close();
    }
  }
}