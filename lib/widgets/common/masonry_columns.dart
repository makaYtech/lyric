import 'package:flutter/material.dart';

/// Раскладка карточек по [columns] колонкам разной высоты, порядок — по
/// строкам. Не ленивая: подходит для десятков карточек, не для сотен.
class MasonryColumns extends StatelessWidget {
  final int columns;
  final double spacing;
  final List<Widget> children;

  const MasonryColumns({
    super.key,
    required this.columns,
    required this.children,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final n = columns < 1 ? 1 : columns;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < n; c++) ...[
          if (c > 0) SizedBox(width: spacing),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = c; i < children.length; i += n) ...[
                  if (i > c) SizedBox(height: spacing),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
