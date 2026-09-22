import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Настройки расписания: объединение в пары, показ ручных правок, окна.
class SchedulePrefs {
  SchedulePrefs._();

  static const _mergePairsKey = 'merge_lesson_pairs';
  static const _showOverridesKey = 'schedule_show_overrides';
  static const _showGapsKey = 'schedule_show_gaps';
  static const _gapThresholdKey = 'schedule_gap_threshold_min';
  static const _autoScrollToTodayKey = 'schedule_auto_scroll_to_today';
  static final CacheService _cache = CacheService();

  /// Минимальная длина разрыва между уроками, при которой он ещё
  /// считается обычной переменой и окно не рисуется.
  static const defaultGapThresholdMin = 20;

  /// Допустимые значения для UI-выбора порога.
  static const gapThresholdOptions = <int>[10, 15, 20, 30, 45];

  static final ValueNotifier<bool> mergePairs = ValueNotifier<bool>(false);

  /// Показывать ли ручные правки расписания. Если false — расписание
  /// рисуется строго по данным сервера.
  static final ValueNotifier<bool> showOverrides = ValueNotifier<bool>(true);

  /// Рисовать ли карточку «Окно» между уроками с большим разрывом.
  static final ValueNotifier<bool> showGaps = ValueNotifier<bool>(true);

  /// Порог в минутах. Разрыв > порога → окно.
  static final ValueNotifier<int> gapThresholdMinutes = ValueNotifier<int>(
    defaultGapThresholdMin,
  );

  /// При первом заходе на вкладку «Расписание» прокручивать к текущему
  /// дню. Срабатывает только один раз за жизнь экрана — при повторных
  /// переключениях вкладки позиция сохраняется.
  static final ValueNotifier<bool> autoScrollToToday = ValueNotifier<bool>(
    true,
  );

  static Future<void> load() async {
    mergePairs.value = (await _cache.loadInt(_mergePairsKey)) == 1;
    final s = await _cache.loadInt(_showOverridesKey);
    showOverrides.value = s == null ? true : s == 1;
    final g = await _cache.loadInt(_showGapsKey);
    showGaps.value = g == null ? true : g == 1;
    final t = await _cache.loadInt(_gapThresholdKey);
    gapThresholdMinutes.value = t ?? defaultGapThresholdMin;
    final a = await _cache.loadInt(_autoScrollToTodayKey);
    autoScrollToToday.value = a == null ? true : a == 1;
  }

  static Future<void> setMergePairs(bool value) async {
    mergePairs.value = value;
    await _cache.saveInt(_mergePairsKey, value ? 1 : 0);
  }

  static Future<void> setShowOverrides(bool value) async {
    if (showOverrides.value == value) return;
    showOverrides.value = value;
    await _cache.saveInt(_showOverridesKey, value ? 1 : 0);
  }

  static Future<void> setShowGaps(bool value) async {
    if (showGaps.value == value) return;
    showGaps.value = value;
    await _cache.saveInt(_showGapsKey, value ? 1 : 0);
  }

  static Future<void> setGapThresholdMinutes(int value) async {
    if (gapThresholdMinutes.value == value) return;
    gapThresholdMinutes.value = value;
    await _cache.saveInt(_gapThresholdKey, value);
  }

  static Future<void> setAutoScrollToToday(bool value) async {
    if (autoScrollToToday.value == value) return;
    autoScrollToToday.value = value;
    await _cache.saveInt(_autoScrollToTodayKey, value ? 1 : 0);
  }
}
