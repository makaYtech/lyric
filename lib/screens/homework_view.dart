import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/settings/homework_prefs.dart';
import '../core/util/labels.dart';
import '../models/homework.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/homework/homework_card.dart';

class HomeworkView extends StatefulWidget {
  final List<Homework>? homeworks;
  final bool isLoading;
  final String? error;

  /// true, когда вкладка ДЗ — текущая. По переходу false → true
  /// прокручиваем полосу дат так, чтобы выбранный день встал в центр.
  final bool isActive;

  final Future<void> Function() onRefresh;

  const HomeworkView({
    super.key,
    required this.homeworks,
    required this.isLoading,
    required this.error,
    required this.isActive,
    required this.onRefresh,
  });

  @override
  State<HomeworkView> createState() => _HomeworkViewState();
}

class _HomeworkViewState extends State<HomeworkView>
    with AutomaticKeepAliveClientMixin {
  final _itemScrollController = ItemScrollController();
  List<DateTime> _dates = const [];
  int _selectedIndex = 0;

  /// Держим состояние вкладки, пока приложение живо. Выбранный день
  /// и позиция скролла сохраняются при переключении на другие вкладки
  /// и обратно; при перезапуске приложения — сбрасываются.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _recomputeDates();
    HomeworkPrefs.groupByDue.addListener(_onPrefChanged);
    _scheduleScrollToSelected();
  }

  @override
  void didUpdateWidget(covariant HomeworkView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.homeworks, widget.homeworks)) {
      _recomputeDates();
      if (widget.isActive) _scheduleScrollToSelected();
    }

    // Вкладку только что открыли — центрируем выбранный день.
    // Откладываем на время анимации PageView (300ms) + запас, иначе
    // скролл полосы конфликтует с анимацией страницы и лагает.
    if (!oldWidget.isActive && widget.isActive) {
      _scheduleScrollToSelected(delay: const Duration(milliseconds: 350));
    }
  }

  @override
  void dispose() {
    HomeworkPrefs.groupByDue.removeListener(_onPrefChanged);
    super.dispose();
  }

  void _onPrefChanged() {
    if (!mounted) return;
    _recomputeDates();
    setState(() {});
    _scheduleScrollToSelected();
  }

  static bool _hasContent(Homework h) {
    final d =
    h.description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return d.isNotEmpty && d != 'не задано';
  }

  DateTime? _dateFor(Homework h) {
    return HomeworkPrefs.groupByDue.value ? h.dueDate : h.assignedAt;
  }

  void _recomputeDates() {
    final homeworks = widget.homeworks;
    final oldSelected = (_selectedIndex >= 0 && _selectedIndex < _dates.length)
        ? _dates[_selectedIndex]
        : null;

    if (homeworks == null || homeworks.isEmpty) {
      _dates = const [];
      _selectedIndex = 0;
      return;
    }

    final datesWithHw = <DateTime>{};
    for (final h in homeworks) {
      if (!_hasContent(h)) continue;
      final d = _dateFor(h);
      if (d != null) {
        datesWithHw.add(DateTime(d.year, d.month, d.day));
      }
    }
    if (datesWithHw.isEmpty) {
      _dates = const [];
      _selectedIndex = 0;
      return;
    }

    final sorted = datesWithHw.toList()..sort();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final past = sorted.where((d) => !d.isAfter(today)).toList();
    final future = sorted.where((d) => d.isAfter(today)).toList();

    final display = <DateTime>[];
    if (past.isNotEmpty) {
      var cursor = past.first;
      while (!cursor.isAfter(today)) {
        display.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    display.addAll(future);

    _dates = display;

    int idx = -1;
    if (oldSelected != null) {
      idx = display.indexWhere((d) => d == oldSelected);
    }
    if (idx < 0) {
      // Первое открытие: сегодня. Если сегодня не в диапазоне —
      // первая дата ≥ сегодня, иначе — последняя.
      idx = display.indexWhere((d) => !d.isBefore(today));
      if (idx < 0) idx = display.length - 1;
    }
    _selectedIndex = idx.clamp(0, display.length - 1);
  }

  void _scheduleScrollToSelected({Duration? delay}) {
    if (delay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    } else {
      Future.delayed(delay, () {
        if (mounted) _scrollToSelected();
      });
    }
  }

  Future<void> _scrollToSelected() async {
    if (!mounted) return;
    if (_selectedIndex < 0 || _selectedIndex >= _dates.length) return;
    if (!_itemScrollController.isAttached) return;

    // В полосе пункты идут парами: чип + разделитель. Значит индекс
    // чипа = 2 * _selectedIndex (см. _DateStrip).
    final target = _selectedIndex * 2;
    _itemScrollController.scrollTo(
      index: target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.5, // 0.5 = центр вьюпорта
    );
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    _scrollToSelected();
  }

  List<Homework> _forSelectedDate() {
    if (_dates.isEmpty) return const [];
    final d = _dates[_selectedIndex];
    final list = (widget.homeworks ?? const <Homework>[])
        .where((h) => _hasContent(h) && _sameDay(_dateFor(h), d))
        .toList();
    list.sort((a, b) => (a.subjectName ?? '').compareTo(b.subjectName ?? ''));
    return list;
  }

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    super.build(context); // требуется AutomaticKeepAliveClientMixin

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: AsyncStateView(
        isLoading: widget.isLoading,
        error: widget.error,
        hasData: _dates.isNotEmpty,
        contentBuilder: (context) {
          final items = _forSelectedDate();
          return ValueListenableBuilder<bool>(
            valueListenable: HomeworkPrefs.groupByDue,
            builder: (context, groupByDue, _) => Column(
              children: [
                _ModeSwitcher(
                  groupByDue: groupByDue,
                  onChanged: HomeworkPrefs.setGroupByDue,
                ),
                _DateStrip(
                  dates: _dates,
                  selectedIndex: _selectedIndex,
                  onSelected: _select,
                  itemScrollController: _itemScrollController,
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('Нет ДЗ на этот день')),
                    ],
                  )
                      : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => HomeworkCard(homework: items[i]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Переключатель режима группировки. Лейбл «Ещё немного — и кранты» —
/// переключает между «по дню, когда задали» и «по дню дедлайна».
class _ModeSwitcher extends StatelessWidget {
  final bool groupByDue;
  final ValueChanged<bool> onChanged;

  const _ModeSwitcher({
    required this.groupByDue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ещё немного — и кранты',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  groupByDue
                      ? 'Дедлайн — на выбранный день'
                      : 'Задано в выбранный день',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: groupByDue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Полоса дат: каждая дата — чип, между чипами — разделители
/// (пустое место / вертикальная черта недели / метка месяца).
///
/// Использует ленивый `ScrollablePositionedList`, чтобы строить только
/// видимые чипы. Общее количество пунктов = 2 * dates.length - 1
/// (чередование чип/разделитель). Чип с датой `i` — на пункте `2*i`.
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

    // Общее число пунктов: N чипов + (N-1) разделителей.
    final itemCount = dates.length * 2 - 1;

    return SizedBox(
      height: 80,
      child: ScrollablePositionedList.builder(
        itemScrollController: itemScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, i) {
          // Чётные — чипы, нечётные — разделители.
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

          // Разделитель между dateIndex = (i-1)/2 и (i+1)/2.
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