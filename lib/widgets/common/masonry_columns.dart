import 'package:flutter/material.dart';

/// Раскладка карточек по [columns] колонкам разной высоты (как «кладка»).
///
/// Порядок — по строкам: 1-я карточка в 1-й колонке, 2-я во 2-й, … потом
/// снова с 1-й. Так алфавитный порядок читается слева направо, а карточки
/// разной высоты не растягиваются до самой высокой в ряду.
///
/// Колонки не ленивые — подходит для десятков карточек (оценки по
/// предметам), не для сотен. Кладётся в SingleChildScrollView.
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
