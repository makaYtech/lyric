import '../../../core/network/api_client.dart';
import '../../../domain/common/academic_year.dart';
import './api_endpoints.dart';
import './auth_service.dart';

class AcademicYearsService {
  final ApiClient _api;
  AcademicYearsService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<AcademicYear>> fetchYears(EposTokens tokens) => _api.getTyped(
    eposUri('/core/api/academic_years', {'pid': tokens.profileId}),
    tokens,
    attempts: 3,
    parse: AcademicYear.fromJson,
  );
}
