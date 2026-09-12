import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Настройка "объединять уроки в пары" — глобальная, читается и в
/// расписании (для отрисовки), и в настройках (для тумблера).
/// ValueNotifier, а не просто bool в CacheService, чтобы экран
/// расписания сразу перерисовался при переключении в настройках.
class SchedulePrefs {
  SchedulePrefs._();

  static const _key = 'merge_lesson_pairs';
  static final CacheService _cache = CacheService();

  static final ValueNotifier<bool> mergePairs = ValueNotifier<bool>(false);

  static Future<void> load() async {
    mergePairs.value = (await _cache.loadInt(_key)) == 1;
  }

  static Future<void> setMergePairs(bool value) async {
    mergePairs.value = value;
    await _cache.saveInt(_key, value ? 1 : 0);
  }
}