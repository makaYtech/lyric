import 'dart:convert';

import 'package:http/http.dart' as http;

import 'myschool_tokens.dart';

/// Клиент API «Моей школы». Все данные идут через единственный POST
/// /api/myschool/v1/datamart — в теле массив запросов, в ответе массив
/// таких же по порядку ответов (с полем data внутри).
class MySchoolApiClient {
  static const _base = 'https://www.gosuslugi.ru/api/myschool/v1';

  Future<List<dynamic>> datamart(
      MySchoolTokens tokens,
      List<Map<String, dynamic>> requests,
      ) async {
    if (requests.isEmpty) return const [];

    final ts = DateTime.now().millisecondsSinceEpoch / 1000;
    final uri = Uri.parse('$_base/datamart?_=$ts');

    final client = http.Client();
    try {
      final resp = await client.post(
        uri,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'content-type': 'application/json',
          'cookie': tokens.cookieHeader,
          'origin': 'https://www.gosuslugi.ru',
          'referer': 'https://www.gosuslugi.ru/school/feed',
        },
        body: jsonEncode(requests),
      );
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const MySchoolSessionExpired();
      }
      if (resp.statusCode != 200) {
        throw Exception('datamart вернул ${resp.statusCode}');
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      return decoded is List ? decoded : const [];
    } finally {
      client.close();
    }
  }
}

class MySchoolSessionExpired implements Exception {
  const MySchoolSessionExpired();
  @override
  String toString() => 'Сессия «Моей школы» истекла';
}