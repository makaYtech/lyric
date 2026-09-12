import 'dart:convert';
import '../core/network/epos_http_client.dart';
import '../models/academic_year.dart';
import 'auth_service.dart';
import 'epos_response_guard.dart';

class AcademicYearsService {
  Future<List<AcademicYear>> fetchYears(EposTokens tokens) async {
    final url = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/academic_years'
      '?pid=${tokens.profileId}',
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
      ensureSessionValid(response);
      if (response.statusCode != 200) {
        throw Exception(
          'Сервер вернул ${response.statusCode}: ${response.body}',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return decoded
          .map((e) => AcademicYear.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      client.close();
    }
  }
}
