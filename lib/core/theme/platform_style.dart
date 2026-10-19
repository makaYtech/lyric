import 'dart:io';

import 'package:flutter/material.dart';

import '../window/mica.dart';

/// Платформенный «характер» оформления.
///
/// Виджеты везде остаются Material 3, а меняется только ThemeData:
/// радиусы, плотность, обводки вместо теней, шрифт и реакция на нажатие.
/// На Windows дополнительно подменяются нейтральные поверхности на серые
/// Fluent (как в «Параметрах»), а акцент остаётся из выбранной темы.
enum AppPlatformStyle {
  /// Android и всё остальное: стандартный Material 3.
  material,

  /// Windows 11: Fluent / WinUI 3.
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

// ── Windows / Fluent ──────────────────────────────────────────────────────
//
// Числа взяты из WinUI 3: ControlCornerRadius = 4, OverlayCornerRadius = 8,
// кнопки 32 px высотой, карточки — полупрозрачная заливка + обводка 1 px,
// поверхности нейтрально-серые (без оттенка акцента, как в Material 3).

ColorScheme _fluentNeutrals(ColorScheme cs, bool dark) {
  return cs.copyWith(
    surfaceTint: Colors.transparent,
    surface: dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
    surfaceContainerLowest: dark
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark
        ? const Color(0xFF252525)
        : const Color(0xFFF9F9F9),
    surfaceContainer: dark ? const Color(0xFF2B2B2B) : const Color(0xFFF0F0F0),
    surfaceContainerHigh: dark
        ? const Color(0xFF303030)
        : const Color(0xFFEBEBEB),
    surfaceContainerHighest: dark
        ? const Color(0xFF363636)
        : const Color(0xFFE6E6E6),
    onSurface: dark ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A1A),
    onSurfaceVariant: dark ? const Color(0xFFC5C5C5) : const Color(0xFF5F5F5F),
    outline: dark ? const Color(0xFF8A8A8A) : const Color(0xFF7A7A7A),
    outlineVariant: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
    // Выбранный пункт / «тональная» кнопка в Fluent — нейтральная подсветка.
    secondaryContainer: dark
        ? const Color(0xFF383838)
        : const Color(0xFFE5E5E5),
    onSecondaryContainer: dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1A1A1A),
  );
}

ThemeData _windows(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final cs = _fluentNeutrals(base.colorScheme, dark);

  // Пересобираем ThemeData с новой схемой, а не copyWith: иначе цвета текста,
  // разделителей и hover останутся вычисленными из старой схемы.
  final t = ThemeData(useMaterial3: true, colorScheme: cs);

  const r4 = BorderRadius.all(Radius.circular(4));
  const r8 = BorderRadius.all(Radius.circular(8));
  final shape4 = RoundedRectangleBorder(borderRadius: r4);
  final shape4Prop = WidgetStatePropertyAll<OutlinedBorder>(shape4);
  const buttonMin = WidgetStatePropertyAll<Size>(Size(64, 32));
  const buttonPad = WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(horizontal: 12),
  );

  // Fluent: карточка = полупрозрачная заливка + тонкая обводка. Поверх Mica
  // она даёт тот самый «слоёный» вид, как у плиток в Параметрах.
  final cardFill = dark ? const Color(0x0DFFFFFF) : const Color(0xB3FFFFFF);
  final cardStroke = dark ? const Color(0x19000000) : const Color(0x0F000000);
  // Flyout (диалоги, меню, подсказки) — сплошные.
  final flyoutFill = dark ? const Color(0xFF2B2B2B) : const Color(0xFFFAFAFA);
  final flyoutBorder = BorderSide(color: cs.outlineVariant);

  return t.copyWith(
    visualDensity: VisualDensity.compact,
    // Fluent не рисует «волну» от нажатия — только подсветку при наведении.
    splashFactory: NoSplash.splashFactory,
    // Поверх Mica фон должен быть прозрачным, иначе подложки не видно.
    scaffoldBackgroundColor: Mica.enabled ? Colors.transparent : cs.surface,
    canvasColor: Mica.enabled ? Colors.transparent : cs.surface,
    textTheme: t.textTheme.apply(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const ['Segoe UI', 'Roboto'],
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: r4,
        side: BorderSide(color: cardStroke),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 8,
      backgroundColor: flyoutFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r8, side: flyoutBorder),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 8,
      color: flyoutFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r8, side: flyoutBorder),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: flyoutFill,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        side: flyoutBorder,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      textStyle: TextStyle(color: cs.onSurface, fontSize: 12),
      decoration: BoxDecoration(
        color: flyoutFill,
        borderRadius: r4,
        border: Border.fromBorderSide(flyoutBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: shape4Prop,
        minimumSize: buttonMin,
        padding: buttonPad,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: shape4Prop,
        minimumSize: buttonMin,
        padding: buttonPad,
        side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: shape4Prop,
        minimumSize: buttonMin,
        padding: buttonPad,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(shape: shape4Prop)),
    listTileTheme: ListTileThemeData(shape: shape4),
    chipTheme: ChipThemeData(
      shape: shape4,
      side: BorderSide(color: cs.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: cardFill,
      border: OutlineInputBorder(
        borderRadius: r4,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r4,
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r4,
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(5),
      thickness: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.hovered) ? 10.0 : 4.0,
      ),
      thumbColor: WidgetStatePropertyAll(cs.onSurface.withValues(alpha: 0.45)),
    ),
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
  );
}

// ── Linux ─────────────────────────────────────────────────────────────────

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
