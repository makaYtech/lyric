import 'dart:io';

import 'package:flutter/material.dart';

/// Платформенный «характер» оформления.
///
/// Виджеты везде остаются Material 3, а меняется только ThemeData:
/// радиусы, плотность, обводки вместо теней, шрифт и реакция на нажатие.
/// Цвета сюда не входят — они приходят из выбранной темы (в режиме
/// «Material» — акцент системы через dynamic_color).
enum AppPlatformStyle {
  /// Android и всё остальное: стандартный Material 3.
  material,

  /// Windows 11: прямоугольнее, без теней, шрифт Segoe UI.
  windows,

  /// Linux: мягкие скругления в духе libadwaita.
  linux;

  static AppPlatformStyle get current {
    if (Platform.isWindows) return AppPlatformStyle.windows;
    if (Platform.isLinux) return AppPlatformStyle.linux;
    return AppPlatformStyle.material;
  }
}

/// Накладывает платформенный стиль поверх готовой темы.
ThemeData applyPlatformStyle(ThemeData base, {AppPlatformStyle? style}) {
  return switch (style ?? AppPlatformStyle.current) {
    AppPlatformStyle.material => base,
    AppPlatformStyle.windows => _windows(base),
    AppPlatformStyle.linux => _linux(base),
  };
}

ThemeData _windows(ThemeData base) {
  final cs = base.colorScheme;
  final r8 = BorderRadius.circular(8);
  final r6 = BorderRadius.circular(6);
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: r6),
  );
  const buttonMin = WidgetStatePropertyAll<Size>(Size(64, 36));

  return base.copyWith(
    visualDensity: VisualDensity.compact,
    // Fluent не рисует «волну» от нажатия — только подсветка при наведении.
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const ['Segoe UI', 'Roboto'],
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: r8,
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: r8),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: r8),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: buttonShape, minimumSize: buttonMin),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(shape: buttonShape, minimumSize: buttonMin),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: buttonShape, minimumSize: buttonMin),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
  );
}

ThemeData _linux(ThemeData base) {
  final cs = base.colorScheme;
  final r12 = BorderRadius.circular(12);
  final r8 = BorderRadius.circular(8);
  final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(borderRadius: r8),
  );

  return base.copyWith(
    visualDensity: VisualDensity.compact,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: r12,
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: r12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
  );
}
