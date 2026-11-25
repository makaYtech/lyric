import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пользовательский выбор оформления. Отдельный enum, а не ThemeMode:
/// «Material» — режим с динамическими цветами Android 12+.
enum AppThemeChoice { light, dark, system, material }

/// Хранит выбранную тему между запусками. По умолчанию — тёмная.
/// Динамические цвета (Material You) — только в режиме «Material».
class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  AppThemeChoice _choice;
  ThemeController._(this._choice);

  AppThemeChoice get choice => _choice;

  /// Что передать в `MaterialApp.themeMode`; «Material» следует системе.
  ThemeMode get mode => switch (_choice) {
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.dark => ThemeMode.dark,
    AppThemeChoice.system => ThemeMode.system,
    AppThemeChoice.material => ThemeMode.system,
  };

  /// Динамические цвета — только при явном выборе «Material».
  bool get useMaterialYou => _choice == AppThemeChoice.material;

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final choice = switch (saved) {
      'light' => AppThemeChoice.light,
      'system' => AppThemeChoice.system,
      'material' => AppThemeChoice.material,
      _ => AppThemeChoice.dark,
    };
    return ThemeController._(choice);
  }

  Future<void> setChoice(AppThemeChoice choice) async {
    if (_choice == choice) return;
    _choice = choice;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, choice.name);
  }
}
