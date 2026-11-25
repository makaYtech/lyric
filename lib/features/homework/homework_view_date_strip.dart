part of 'homework_view.dart';

class _DateStrip extends StatelessWidget {
  final List<DateTime> dates;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ItemScrollController itemScrollController;

  const _DateStrip({
    required this.dates,
    required this.selectedIndex,
    required this.onSelected,
    required this.itemScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final itemCount = dates.length * 2 - 1;

    return SizedBox(
      height: 80,
      child: ScrollablePositionedList.builder(
        itemScrollController: itemScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, i) {
          if (i.isEven) {
            final dateIndex = i ~/ 2;
            final d = dates[dateIndex];
            return _DateChip(
              date: d,
              selected: dateIndex == selectedIndex,
              isToday: d == today,
              onTap: () => onSelected(dateIndex),
            );
          }

          final prev = dates[(i - 1) ~/ 2];
          final cur = dates[(i + 1) ~/ 2];
          if (cur.month != prev.month) {
            return _MonthSeparator(month: cur.month);
          }
          if (cur.weekday == DateTime.monday) {
            return const _WeekSeparator();
          }
          return const SizedBox(width: 6);
        },
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  const _DateChip({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = kWeekdaysShort[date.weekday - 1];
    final dayMonth = '${date.day}.${date.month.toString().padLeft(2, '0')}';

    final onColor = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    final subColor = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return ChoiceChip(
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
      onSelected: (_) => onTap(),
      selectedColor: theme.colorScheme.secondaryContainer,
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      side: BorderSide(
        color: selected
            ? theme.colorScheme.secondary
            : (isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant),
      ),
    );
  }
}

class _MonthSeparator extends StatelessWidget {
  final int month;

  const _MonthSeparator({required this.month});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Text(
          kMonthsShort[month - 1],
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _WeekSeparator extends StatelessWidget {
  const _WeekSeparator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.colorScheme.outlineVariant,
    );
  }
}
