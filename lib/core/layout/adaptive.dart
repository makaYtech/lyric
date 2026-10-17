import 'dart:io';

/// Всё, что решает «какой интерфейс показывать», живёт здесь.
///
/// Раскладка выбирается по ШИРИНЕ ОКНА, а не по платформе: так Android-планшет
/// и узкое окно на ПК ведут себя предсказуемо. Платформа нужна только для
/// того, что от неё реально зависит (кнопка раскрытия панели, webview).
abstract final class AdaptiveLayout {
  /// С этой ширины (в логических px) нижний бар заменяется боковой панелью.
  /// 840 — граница «expanded» у Material 3.
  static const double sideBarBreakpoint = 840;

  static bool useSideBar(double width) => width >= sideBarBreakpoint;

  /// Ширина самой ОБЛАСТИ КОНТЕНТА (а не окна), с которой вкладки
  /// переключаются с одного столбца на сетку/колонки. Окно 840 px минус
  /// свёрнутая панель (72) даёт ~770, так что на минимальном «широком»
  /// окне уже работает сетка.
  static const double wideContentBreakpoint = 700;

  static bool wideContent(double contentWidth) =>
      contentWidth >= wideContentBreakpoint;

  static bool get isDesktopOS =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// Кнопка «свернуть/развернуть» в панели. На Android её нет.
  static bool get canToggleSideBar => !Platform.isAndroid;

  /// webview_flutter реализован только для Android и iOS.
  /// На desktop вызов WebViewController() падает assert'ом.
  static bool get webViewSupported => Platform.isAndroid || Platform.isIOS;
}
