import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Простой кэш поверх SharedPreferences — для СТАТИЧЕСКИХ и небольших
/// данных: профиль ученика, выбранный учебный год, прочие настройки.
///
/// Тяжёлые и часто меняющиеся данные (оценки, расписание) сюда не пишем —
/// для них есть ScheduleDao/GradesDao поверх SQLite (core/db).
///
/// JSON-методы (save/load) автоматически ставят метку времени —
/// ей пользуется lastUpdated(). Int-методы — для простых настроек
/// вроде выбранного учебного года, без метки времени.
class CacheService {
  static const _timestampSuffix = '_updated_at';

  Future<void> save(String key, Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(json));
    await _touchTimestamp(prefs, key);
  }

  Future<void> saveList(
      String key,
      List<Map<String, dynamic>> jsonList,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(jsonList));
    await _touchTimestamp(prefs, key);
  }

  Future<Map<String, dynamic>?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>?> loadList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> lastUpdated(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$key$_timestampSuffix');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  Future<int?> loadInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }

  Future<void> _touchTimestamp(SharedPreferences prefs, String key) async {
    await prefs.setString(
      '$key$_timestampSuffix',
      DateTime.now().toIso8601String(),
    );
  }

  /// Сносит всё, что мы положили, кроме темы оформления (она не
  /// относится к данным пользователя). Используется при logout.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key == 'theme_mode') continue;
      await prefs.remove(key);
    }
  }
}