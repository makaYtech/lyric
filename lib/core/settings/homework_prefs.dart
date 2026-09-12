import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Настройка вкладки ДЗ: группировать по дате выдачи («задано в этот
/// день», по умолчанию) или по дедлайну («сделать до этого дня»).
/// ValueNotifier, чтобы экран ДЗ сразу перерисовывался при переключении.
class HomeworkPrefs {
  HomeworkPrefs._();

  static const _key = 'homework_group_by_due';
  static final CacheService _cache = CacheService();

  /// false — «по дню, когда задали» (date_assigned_on);
  /// true  — «по дню, на который дедлайн» (date_prepared_for).
  static final ValueNotifier<bool> groupByDue = ValueNotifier<bool>(false);

  static Future<void> load() async {
    groupByDue.value = (await _cache.loadInt(_key)) == 1;
  }

  static Future<void> setGroupByDue(bool value) async {
    groupByDue.value = value;
    await _cache.saveInt(_key, value ? 1 : 0);
  }
}