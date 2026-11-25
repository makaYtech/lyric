import 'package:flutter/material.dart';

/// Тело нижней шторки: вертикальный скролл с выделяемым текстом.
///
/// [AlwaysScrollableScrollPhysics] нужен, чтобы DraggableScrollableSheet
/// мог расширяться, даже когда контент короче экрана.
class ScrollableSheetBody extends StatelessWidget {
  final ScrollController? controller;
  final List<Widget> children;

  const ScrollableSheetBody({
    super.key,
    this.controller,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SelectionArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}
