import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Группировка ДЗ: по дате выдачи (по умолчанию) или по дедлайну.
/// ValueNotifier перерисовывает экран ДЗ сразу при переключении.
class HomeworkPrefs {
  HomeworkPrefs._();

  static const _key = 'homework_group_by_due';
  static final CacheService _cache = CacheService();

  /// false — date_assigned_on, true — date_prepared_for.
  static final ValueNotifier<bool> groupByDue = ValueNotifier<bool>(false);

  static Future<void> load() async {
    groupByDue.value = (await _cache.loadInt(_key)) == 1;
  }

  static Future<void> setGroupByDue(bool value) async {
    groupByDue.value = value;
    await _cache.saveInt(_key, value ? 1 : 0);
  }
}
