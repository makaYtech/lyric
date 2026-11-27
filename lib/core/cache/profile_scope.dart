import 'package:shared_preferences/shared_preferences.dart';

/// Активный профиль для данных: id ребёнка у родителя, id ученика у ученика.
///
/// Пока null — ключи кэша остаются прежними (совместимость со старыми
/// сборками и тестами).
class ProfileScope {
  ProfileScope._();

  static const _timestampSuffix = '_updated_at';

  /// Данные, которые до появления профилей лежали без префикса.
  static const _legacyKeys = [
    'profile',
    'academic_years',
    'student_groups',
    'selected_academic_year_id',
    'student_teacher_ids',
    'ec_group_ids',
  ];

  static String? _profileId;

  static String? get profileId => _profileId;

  static void set(String? profileId) {
    _profileId = (profileId == null || profileId.isEmpty) ? null : profileId;
  }

  static String key(String key) =>
      _profileId == null ? key : 'p$_profileId:$key';

  /// Переносит старый общий кэш в текущий профиль (один раз после
  /// обновления). Вызывать только для собственного профиля ученика.
  static Future<void> migrateLegacyData() async {
    final id = _profileId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in _legacyKeys) {
      final scoped = 'p$id:$key';
      if (prefs.containsKey(scoped)) continue;
      final value = prefs.get(key);
      if (value != null) {
        if (value is String) {
          await prefs.setString(scoped, value);
        } else if (value is int) {
          await prefs.setInt(scoped, value);
        } else if (value is bool) {
          await prefs.setBool(scoped, value);
        } else if (value is double) {
          await prefs.setDouble(scoped, value);
        } else if (value is List<String>) {
          await prefs.setStringList(scoped, value);
        }
      }
      final updated = prefs.getString('$key$_timestampSuffix');
      if (updated != null) {
        await prefs.setString('$scoped$_timestampSuffix', updated);
      }
      await prefs.remove(key);
      await prefs.remove('$key$_timestampSuffix');
    }
  }
}
