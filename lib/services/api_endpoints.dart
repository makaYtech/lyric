class ApiEndpoints {
  ApiEndpoints._();

  /// Базовый префикс для core-ручек (student_profiles и т.д.)
  static const String coreBase = 'https://edu-epos.permkrai.ru/core/api';

  /// Базовый префикс для acl-ручек (users и т.д.)
  static const String aclBase = 'https://edu-epos.permkrai.ru/acl/api';

  /// /student_profiles/{id}?pid={id}
  static Uri studentProfile(String profileId) =>
      Uri.parse('$coreBase/student_profiles/$profileId?pid=$profileId');

  /// /users?ids={ids}&pid={pid}
  static Uri users(String userIds, String profileId) =>
      Uri.parse('$aclBase/users?ids=$userIds&pid=$profileId');

  static Uri studentProfileWithAttendance(String profileId, int yearId) =>
      Uri.parse(
        '$coreBase/student_profiles/$profileId'
        '?academic_year_id=$yearId'
        '&with_attendance=true'
        '&pid=$profileId',
      );
}
