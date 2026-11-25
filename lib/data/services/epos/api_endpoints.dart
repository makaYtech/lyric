const String eposBase = 'https://edu-epos.permkrai.ru';

/// Собирает URL ЭПОСа, не кодируя запятые: сервер ждёт списки id
/// (`group_id=1,2,3`) в сыром виде и отвечает 400 на `%2C`.
Uri eposUri(String path, [Map<String, Object?> query = const {}]) {
  final buffer = StringBuffer(eposBase)
    ..write(path.startsWith('/') ? path : '/$path');
  var hasQuery = false;
  query.forEach((key, value) {
    if (value == null) return;
    buffer.write(hasQuery ? '&' : '?');
    hasQuery = true;
    buffer.write('$key=${_queryValue(value)}');
  });
  return Uri.parse(buffer.toString());
}

String _queryValue(Object value) =>
    Uri.encodeQueryComponent(value.toString()).replaceAll('%2C', ',');

class ApiEndpoints {
  ApiEndpoints._();

  static const String coreBase = '$eposBase/core/api';
  static const String aclBase = '$eposBase/acl/api';

  /// /student_profiles/{id}?pid={id}
  static Uri studentProfile(String profileId) =>
      eposUri('/core/api/student_profiles/$profileId', {'pid': profileId});

  /// /users?ids={ids}&pid={pid}
  static Uri users(String userIds, String profileId) =>
      eposUri('/acl/api/users', {'ids': userIds, 'pid': profileId});

  static Uri studentProfileWithAttendance(String profileId, int yearId) =>
      eposUri('/core/api/student_profiles/$profileId', {
        'academic_year_id': yearId,
        'with_attendance': true,
        'pid': profileId,
      });
}
