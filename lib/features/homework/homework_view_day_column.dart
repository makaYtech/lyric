part of 'homework_view.dart';

/// Круглая кнопка листания по краю области колонок.
class _EdgeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _EdgeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Колонка одного дня: шапка и список карточек. Сегодняшний день выделен
/// отдельно от выбранного: полоса сверху, плашка «сегодня», тон колонки.
class _DayColumn extends StatelessWidget {
  final DateTime date;
  final List<Homework> items;
  final bool selected;
  final bool showDivider;
  final VoidCallback onHeaderTap;

  const _DayColumn({
    required this.date,
    required this.items,
    required this.selected,
    required this.showDivider,
    required this.onHeaderTap,
  });

  /// «сегодня» / «завтра» / «вчера» или null.
  static String? _relative(DateTime date) {
    final diff = dayOnly(date).difference(dayOnly(DateTime.now())).inDays;
    return switch (diff) {
      0 => 'сегодня',
      1 => 'завтра',
      -1 => 'вчера',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final relative = _relative(date);
    final isToday = relative == 'сегодня';

    final weekday = kWeekdaysShort[date.weekday - 1];
    final dayMonth = '${date.day}.${date.month.toString().padLeft(2, '0')}';

    final headerFg = selected ? cs.onSecondaryContainer : cs.onSurface;
    final subFg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    final columnTint = isToday
        ? Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface)
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: columnTint,
        border: showDivider
            ? Border(left: BorderSide(color: cs.outlineVariant))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            color: isToday ? cs.primary : Colors.transparent,
          ),
          Material(
            color: selected ? cs.secondaryContainer : Colors.transparent,
            child: InkWell(
              onTap: onHeaderTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Text(
                      '$weekday, $dayMonth',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isToday && !selected ? cs.primary : headerFg,
                      ),
                    ),
                    if (relative != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isToday ? cs.primary : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          relative,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isToday ? cs.onPrimary : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: subFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => HomeworkCard(homework: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}
