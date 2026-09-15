import '../core/network/api_client.dart';
import '../models/academic_year.dart';
import 'auth_service.dart';

class AcademicYearsService {
  final ApiClient _api;
  AcademicYearsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<AcademicYear>> fetchYears(EposTokens tokens) async {
    final url = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/academic_years'
          '?pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(url, tokens, attempts: 3);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AcademicYear.fromJson)
        .toList();
  }
}