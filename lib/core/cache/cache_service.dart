import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import './profile_scope.dart';

/// Кэш поверх SharedPreferences для статических и небольших данных:
/// профиль, выбранный учебный год, настройки. Тяжёлые данные — в SQLite.
///
/// JSON-методы ставят метку времени для lastUpdated(); int-методы — без неё.
///
/// `scoped: true` — данные конкретного профиля (оценки, годы, выбранный
/// год): ключи получают префикс активного ребёнка/ученика. Настройки
/// приложения остаются общими.
class CacheService {
  static const _timestampSuffix = '_updated_at';

  final bool scoped;

  CacheService({this.scoped = false});

  String _key(String key) => scoped ? ProfileScope.key(key) : key;

  Future<void> save(String key, Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), jsonEncode(json));
    await _touchTimestamp(prefs, _key(key));
  }

  Future<void> saveList(String key, List<Map<String, dynamic>> jsonList) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), jsonEncode(jsonList));
    await _touchTimestamp(prefs, _key(key));
  }

  Future<Map<String, dynamic>?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(key));
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
    final raw = prefs.getString(_key(key));
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
    final raw = prefs.getString('${_key(key)}$_timestampSuffix');
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(key), value);
  }

  Future<int?> loadInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(key));
  }

  Future<void> saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), value);
  }

  Future<String?> loadString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(key));
  }

  /// Снести запись вместе с timestamp'ом (девелоперский сброс).
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(key));
    await prefs.remove('${_key(key)}$_timestampSuffix');
  }

  Future<void> _touchTimestamp(SharedPreferences prefs, String key) async {
    await prefs.setString(
      '$key$_timestampSuffix',
      DateTime.now().toIso8601String(),
    );
  }

  /// Сносит всё, кроме темы оформления. Используется при logout.
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (key == 'theme_mode') continue;
      await prefs.remove(key);
    }
  }
}
