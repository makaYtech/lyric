import 'dart:io';

/// Всё, что решает «какой интерфейс показывать». Раскладка выбирается по
/// ширине окна, а не по платформе; платформа — только для реально
/// платформенных вещей (кнопка панели, webview).
abstract final class AdaptiveLayout {
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

  /// Кнопка «свернуть/развернуть» в панели. На Android её нет.
  static bool get canToggleSideBar => !Platform.isAndroid;

  /// webview_flutter есть только на Android и iOS; на desktop
  /// WebViewController() падает assert'ом.
  static bool get webViewSupported => Platform.isAndroid || Platform.isIOS;
}
