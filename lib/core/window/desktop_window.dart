import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../layout/adaptive.dart';

/// Окно на desktop: минимальный размер, запоминание размера между запусками.
///
/// Позицию окна не сохраняем: на Wayland приложение не может ею управлять
/// (композитор решает сам), а на X11/Windows запоминание позиции часто
/// заканчивается окном за краем экрана после смены мониторов.
class DesktopWindow with WindowListener {
  DesktopWindow._();
  static final DesktopWindow _instance = DesktopWindow._();

  /// Ниже этого размера интерфейс не сжимается: 420 px — телефонная раскладка.
  static const Size minSize = Size(420, 600);
  static const Size _defaultSize = Size(1180, 760);

  static const _wKey = 'window_width';
  static const _hKey = 'window_height';
  static const _maxKey = 'window_maximized';

  Timer? _saveTimer;

  /// Вызывать в main() после ensureInitialized(), до runApp().
  static Future<void> init() async {
    if (!AdaptiveLayout.isDesktopOS) return;

    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_wKey);
    final h = prefs.getDouble(_hKey);
    final hasSaved = w != null && h != null;

    final size = hasSaved
        ? Size(
            w.clamp(minSize.width, 10000).toDouble(),
            h.clamp(minSize.height, 10000).toDouble(),
          )
        : _defaultSize;

    final options = WindowOptions(
      size: size,
      minimumSize: minSize,
      center: !hasSaved,
      title: 'ЭПОС',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
      if (prefs.getBool(_maxKey) ?? false) {
        await windowManager.maximize();
      }
    });

    windowManager.addListener(_instance);
  }

  // ── WindowListener ────────────────────────────────────────────────────

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMaximize() => _saveMaximized(true);

  @override
  void onWindowUnmaximize() => _saveMaximized(false);

  void _scheduleSave() {
    // Размер меняется десятки раз в секунду при перетаскивании края.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveSize);
  }

  Future<void> _saveSize() async {
    try {
      // В развёрнутом состоянии размер «на весь экран» не запоминаем:
      // иначе после сворачивания окно останется огромным.
      if (await windowManager.isMaximized()) return;
      if (await windowManager.isFullScreen()) return;
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_wKey, size.width);
      await prefs.setDouble(_hKey, size.height);
    } catch (_) {
      // Размер окна — не повод падать.
    }
  }

  Future<void> _saveMaximized(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_maxKey, value);
    } catch (_) {}
  }
}
