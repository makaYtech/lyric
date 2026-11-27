import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

/// Всё, что решает «какой интерфейс показывать». Раскладка выбирается по
/// ширине окна, а не по платформе; платформа — только для реально
/// платформенных вещей (кнопка панели, webview).
abstract final class AdaptiveLayout {
  /// true — платформенная реализация webview_flutter зарегистрирована.
  /// На desktop плагин есть в pubspec, но WebViewController создавать
  /// нельзя — бросает assert. В unit-тестах тоже false.
  static bool get hasWebView {
    if (!webViewSupported) return false;
    try {
      WebViewPlatform.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// С этой ширины нижний бар заменяется боковой панелью (граница
  /// «expanded» у Material 3).
  static const double sideBarBreakpoint = 840;

  static bool useSideBar(double width) => width >= sideBarBreakpoint;

  /// Ширина области контента, с которой вкладки переключаются на сетку.
  /// Окно 840 минус свёрнутая панель 72 ≈ 770, так что сетка уже работает.
  static const double wideContentBreakpoint = 700;

  static bool wideContent(double contentWidth) =>
      contentWidth >= wideContentBreakpoint;

  static bool get isDesktopOS =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Кнопка «свернуть/развернуть» в панели. Доступна на всех платформах,
  /// включая Android — панель должна уметь раскрываться и на телефоне.
  static bool get canToggleSideBar => true;

  /// webview_flutter есть только на Android и iOS; на desktop
  /// WebViewController() падает assert'ом.
  static bool get webViewSupported => Platform.isAndroid || Platform.isIOS;
}
