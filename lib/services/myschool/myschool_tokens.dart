import 'dart:convert';

/// Токены и ключи сессии «Моей школы».
///
/// Источник — cookies домена www.gosuslugi.ru после логина через ЕСИА:
///   acc_t     — JWT access token (главное, что проверяет сервер)
///   u         — user_id (числовой)
///   studentId — UUID ученика (для запросов данных именно этого дневника)
///
/// CookieHeader собирается один раз, вручную — http-пакет сам их не
/// подставит, потому что мы не идём через WebView.
class MySchoolTokens {
  final String accT;
  final String userId;
  final String studentId;

  const MySchoolTokens({
    required this.accT,
    required this.userId,
    required this.studentId,
  });

  String get cookieHeader =>
      'acc_t=$accT; u=$userId; studentId=$studentId';

  /// Проверка, что acc_t ещё жив: парсим exp из JWT (base64 payload).
  bool get isExpired {
    final exp = _jwtExp(accT);
    if (exp == null) return false;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 > exp;
  }

  static int? _jwtExp(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) return null;
    try {
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final json = utf8.decode(base64.decode(payload));
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map['exp'] as int?;
    } catch (_) {
      return null;
    }
  }
}