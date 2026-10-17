import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/layout/adaptive.dart';
import '../../core/settings/layout_prefs.dart';

/// Строит содержимое модалки.
///
/// [scrollController] приходит НЕ null только при `draggable: true` — его
/// надо повесить на главный прокручиваемый виджет внутри (как раньше с
/// DraggableScrollableSheet).
typedef AdaptiveSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController? scrollController,
);

/// Единая точка для всех «шторок» приложения.
///
/// Узкое окно (< [AdaptiveLayout.sideBarBreakpoint]) — как раньше, нижняя
/// шторка (`showModalBottomSheet`).
/// Широкое окно:
///  * `draggable: true` (детали урока/ДЗ и т.п.) — боковая панель, въезжает
///    со стороны, противоположной боковому меню;
///  * иначе (оценка, пропуск, список файлов, обновление) — диалог по центру.
/// И то и другое закрывается крестиком, Esc и кликом по затемнению.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required AdaptiveSheetBuilder builder,
  bool draggable = false,
  double initialSize = 0.5,
  double minSize = 0.3,
  double maxSize = 1.0,
  List<double>? snapSizes,
  bool useSafeArea = false,
  bool dismissible = true,
  bool showDragHandle = true,

  /// Содержимое само умеет прокручиваться (внутри свой SingleChildScrollView).
  /// Иначе в диалоге оно будет обёрнуто в прокрутку автоматически.
  bool selfScrolling = false,
  double dialogWidth = 480,
  double panelWidth = 460,
}) {
  final wide = AdaptiveLayout.useSideBar(MediaQuery.sizeOf(context).width);

  if (!wide) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: showDragHandle,
      isScrollControlled: true,
      isDismissible: dismissible,
      enableDrag: dismissible,
      useSafeArea: useSafeArea,
      builder: (ctx) => draggable
          ? DraggableScrollableSheet(
              initialChildSize: initialSize,
              minChildSize: minSize,
              maxChildSize: maxSize,
              snap: snapSizes != null,
              snapSizes: snapSizes,
              expand: false,
              builder: (c, controller) => builder(c, controller),
            )
          : builder(ctx, null),
    );
  }

  if (draggable) {
    // Панель с той стороны, где НЕТ бокового меню.
    final fromRight = !LayoutPrefs.sideBarOnRight.value;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) => _SidePanel(
        width: panelWidth,
        fromRight: fromRight,
        closable: dismissible,
        builder: builder,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(fromRight ? 1 : -1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => _CenteredDialog(
      width: dialogWidth,
      closable: dismissible,
      selfScrolling: selfScrolling,
      child: builder(ctx, null),
    ),
  );
}

/// Верхняя полоска с крестиком — на месте «ручки» нижней шторки.
class _CloseBar extends StatelessWidget {
  final bool closable;
  const _CloseBar({required this.closable});

  @override
  Widget build(BuildContext context) {
    if (!closable) return const SizedBox(height: 20);
    return SizedBox(
      height: 48,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
    );
  }
}

class _CenteredDialog extends StatelessWidget {
  final double width;
  final bool closable;
  final bool selfScrolling;
  final Widget child;

  const _CenteredDialog({
    required this.width,
    required this.closable,
    required this.selfScrolling,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CloseBar(closable: closable),
              Flexible(
                child: selfScrolling
                    ? child
                    : SingleChildScrollView(child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidePanel extends StatefulWidget {
  final double width;
  final bool fromRight;
  final bool closable;
  final AdaptiveSheetBuilder builder;

  const _SidePanel({
    required this.width,
    required this.fromRight,
    required this.closable,
    required this.builder,
  });

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  // Своя прокрутка для содержимого: те же шторки, что и на мобильном,
  // ждут scrollController от DraggableScrollableSheet.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    final w = math.min(widget.width, screenW * 0.9);
    const r = Radius.circular(24);

    return Align(
      alignment: widget.fromRight
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: SizedBox(
        width: w,
        height: double.infinity,
        child: Material(
          color: cs.surfaceContainerLow,
          elevation: 3,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: widget.fromRight
                ? const BorderRadius.horizontal(left: r)
                : const BorderRadius.horizontal(right: r),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CloseBar(closable: widget.closable),
                Expanded(child: widget.builder(context, _scroll)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
