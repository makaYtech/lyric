part of 'schedule_view.dart';

class _WeekSwitcher extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  /// null — уже на текущей неделе, кнопку не показываем.
  final VoidCallback? onToday;
  final VoidCallback? onShowOverrides;
  final int overridesCount;

  const _WeekSwitcher({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    this.onToday,
    this.onShowOverrides,
    this.overridesCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Предыдущая неделя',
              onPressed: onPrev,
            ),
            Expanded(
              child: InkWell(
                onTap: onPick,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _rangeLabel(weekStart),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Следующая неделя',
              onPressed: onNext,
            ),
            if (onToday != null)
              IconButton(
                icon: const Icon(Icons.today),
                tooltip: 'Текущая неделя (Home)',
                onPressed: onToday,
              ),
            if (onShowOverrides != null)
              IconButton(
                icon: Badge(
                  isLabelVisible: overridesCount > 1,
                  label: Text('$overridesCount'),
                  child: const Icon(Icons.rule_folder_outlined),
                ),
                tooltip: 'Правки недели',
                onPressed: onShowOverrides,
              ),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    if (monday.month == sunday.month) {
      return '${monday.day} – ${sunday.day} ${kMonthsGenitive[monday.month - 1]}';
    }
    return '${monday.day} ${kMonthsShort[monday.month - 1]} – '
        '${sunday.day} ${kMonthsShort[sunday.month - 1]}';
  }
}

class _DayStrip extends StatelessWidget {
  final List<DaySchedule> days;
  final int activeIndex;
  final ValueChanged<int> onTap;
  final Set<String> daysWithOverrides;

  const _DayStrip({
    required this.days,
    required this.activeIndex,
    required this.onTap,
    this.daysWithOverrides = const {},
  });

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = days[i];
          final selected = i == activeIndex;
          final isToday = _isToday(d.date);
          final hasLessons = d.lessons.isNotEmpty;
          final hasOverrides = daysWithOverrides.contains(_iso(d.date));

          final weekday = kWeekdaysShort[d.date.weekday - 1];
          final dayMonth =
              '${d.date.day}.${d.date.month.toString().padLeft(2, '0')}';

          final onColor = selected
              ? theme.colorScheme.onSecondaryContainer
              : (hasLessons
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant);
          final subColor = selected
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant;

          final chip = ChoiceChip(
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weekday,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: subColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dayMonth,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    height: 1.0,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(i),
            selectedColor: theme.colorScheme.secondaryContainer,
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            pressElevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.secondary
                  : (isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant),
            ),
          );

          if (!hasOverrides) return chip;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              chip,
              Positioned(
                top: 2,
                right: 6,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
