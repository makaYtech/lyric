import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Настройки раскладки. Сейчас — только боковая панель.
///
/// Работает как AuthConfig: ValueNotifier'ы, значения грузятся один раз
/// в main() через [load] и сохраняются при изменении.
class LayoutPrefs {
  LayoutPrefs._();

  static const _rightKey = 'layout_sidebar_right';
  static const _expandedKey = 'layout_sidebar_expanded';
  static final CacheService _cache = CacheService();

  /// true — панель справа, false — слева.
  static final ValueNotifier<bool> sideBarOnRight = ValueNotifier<bool>(false);

  /// true — панель раскрыта (иконки + названия), false — только иконки.
  static final ValueNotifier<bool> sideBarExpanded = ValueNotifier<bool>(false);

  static Future<void> load() async {
    sideBarOnRight.value = (await _cache.loadInt(_rightKey)) == 1;
    sideBarExpanded.value = (await _cache.loadInt(_expandedKey)) == 1;
  }

  static Future<void> setSideBarOnRight(bool value) async {
    if (sideBarOnRight.value == value) return;
    sideBarOnRight.value = value;
    await _cache.saveInt(_rightKey, value ? 1 : 0);
  }

  static Future<void> setSideBarExpanded(bool value) async {
    if (sideBarExpanded.value == value) return;
    sideBarExpanded.value = value;
    await _cache.saveInt(_expandedKey, value ? 1 : 0);
  }
}
