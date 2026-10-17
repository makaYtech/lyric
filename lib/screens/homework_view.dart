import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/layout/adaptive.dart';
import '../core/settings/homework_prefs.dart';
import '../core/util/labels.dart';
import '../models/homework.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/homework/homework_card.dart';
import '../widgets/homework/homework_group_switcher.dart';

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

  // ── Широкий режим: колонки по дням ────────────────────────────────────
  // Колонки есть только у дней, где реально есть ДЗ (в полосе дат — все дни).
  final _columnsScroll = ItemScrollController();
  final _focus = FocusNode(debugLabel: 'homework');
  List<DateTime> _colDates = const [];
  int _colsPerView = 1;
  Map<DateTime, List<Homework>>? _byDateCache;
  List<Homework>? _byDateCacheForList;

  // Кэш отфильтрованного списка под выбранную дату. Раньше фильтрация
  // (проход по всем ДЗ года) шла на каждый build — теперь только при
  // смене даты / списка / режима группировки.
  List<Homework>? _itemsCache;
  DateTime? _itemsCacheForDate;
  List<Homework>? _itemsCacheForList;

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

    if (!oldWidget.isActive && widget.isActive) {
      _scheduleScrollToSelected(delay: const Duration(milliseconds: 350));
      // Чтобы стрелки ←/→ работали сразу после переключения на вкладку.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    HomeworkPrefs.groupByDue.removeListener(_onPrefChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onPrefChanged() {
    if (!mounted) return;
    _invalidateItemsCache();
    _recomputeDates();
    setState(() {});
    _scheduleScrollToSelected();
  }

  void _invalidateItemsCache() {
    _itemsCache = null;
    _itemsCacheForDate = null;
    _itemsCacheForList = null;
    _byDateCache = null;
    _byDateCacheForList = null;
  }

  static bool _hasContent(Homework h) {
    final d = h.description.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return d.isNotEmpty && d != 'не задано';
  }

  DateTime? _dateFor(Homework h) {
    return HomeworkPrefs.groupByDue.value ? h.dueDate : h.assignedAt;
  }

  void _recomputeDates() {
    _invalidateItemsCache();

    final homeworks = widget.homeworks;
    final oldSelected = (_selectedIndex >= 0 && _selectedIndex < _dates.length)
        ? _dates[_selectedIndex]
        : null;

    if (homeworks == null || homeworks.isEmpty) {
      _dates = const [];
      _colDates = const [];
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
      _colDates = const [];
      _selectedIndex = 0;
      return;
    }

    final sorted = datesWithHw.toList()..sort();
    _colDates = sorted;

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

    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: _selectedIndex * 2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }

    // Широкий режим: выбранный день встаёт в центр области колонок.
    if (_columnsScroll.isAttached && _colDates.isNotEmpty) {
      _columnsScroll.scrollTo(
        index: _selectedColIndex(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: _centerAlignment(),
      );
    }
  }

  /// Колонка выбранного дня. Если у выбранного дня ДЗ нет — ближайшая
  /// следующая с ДЗ (а если таких нет — последняя).
  int _selectedColIndex() {
    if (_colDates.isEmpty || _dates.isEmpty) return 0;
    final sel = _dates[_selectedIndex];
    final i = _colDates.indexWhere((d) => !d.isBefore(sel));
    return i < 0 ? _colDates.length - 1 : i;
  }

  /// alignment для ScrollablePositionedList: где стоит ЛЕВЫЙ край колонки
  /// (доля ширины окна). Для центра: 0.5 − (ширина колонки / 2) / ширина.
  /// Колонок помещается [_colsPerView], значит ширина колонки = 1 / n.
  double _centerAlignment() => (0.5 - 0.5 / _colsPerView).clamp(0.0, 1.0);

  /// Стрелки ←/→: переход к соседнему ДНЮ С ДЗ.
  void _moveSelection(int delta) {
    if (_colDates.isEmpty) return;
    final next = (_selectedColIndex() + delta).clamp(0, _colDates.length - 1);
    final dateIndex = _dates.indexOf(_colDates[next]);
    if (dateIndex < 0) return;
    if (dateIndex == _selectedIndex) {
      _scrollToSelected();
    } else {
      _select(dateIndex);
    }
  }

  Map<DateTime, List<Homework>> _itemsByDate() {
    final list = widget.homeworks;
    if (_byDateCache != null && identical(_byDateCacheForList, list)) {
      return _byDateCache!;
    }
    final map = <DateTime, List<Homework>>{};
    for (final h in list ?? const <Homework>[]) {
      if (!_hasContent(h)) continue;
      final d = _dateFor(h);
      if (d == null) continue;
      map.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(h);
    }
    for (final items in map.values) {
      items.sort(
        (a, b) => (a.subjectName ?? '').compareTo(b.subjectName ?? ''),
      );
    }
    _byDateCache = map;
    _byDateCacheForList = list;
    return map;
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    _invalidateItemsCache();
    setState(() => _selectedIndex = index);
    _scrollToSelected();
  }

  List<Homework> _forSelectedDate() {
    if (_dates.isEmpty) return const [];
    final d = _dates[_selectedIndex];
    final list = widget.homeworks;
    if (_itemsCache != null &&
        _itemsCacheForDate == d &&
        identical(_itemsCacheForList, list)) {
      return _itemsCache!;
    }
    final items = (list ?? const <Homework>[])
        .where((h) => _hasContent(h) && _sameDay(_dateFor(h), d))
        .toList();
    items.sort((a, b) => (a.subjectName ?? '').compareTo(b.subjectName ?? ''));
    _itemsCache = items;
    _itemsCacheForDate = d;
    _itemsCacheForList = list;
    return items;
  }

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Map<ShortcutActivator, VoidCallback> get _bindings => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        _moveSelection(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        _moveSelection(1),
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = AdaptiveLayout.wideContent(constraints.maxWidth);

        final body = AsyncStateView(
          isLoading: widget.isLoading,
          error: widget.error,
          hasData: _dates.isNotEmpty,
          contentBuilder: (context) =>
              wide ? _buildWide(constraints.maxWidth) : _buildNarrow(),
        );

        return CallbackShortcuts(
          bindings: (wide && widget.isActive)
              ? _bindings
              : const <ShortcutActivator, VoidCallback>{},
          child: Focus(
            focusNode: _focus,
            // Pull-to-refresh — только для узкого (тач) режима.
            child: wide
                ? body
                : RefreshIndicator(onRefresh: widget.onRefresh, child: body),
          ),
        );
      },
    );
  }

  Widget _buildNarrow() {
    final items = _forSelectedDate();
    return Column(
      children: [
        const HomeworkGroupSwitcher(),
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
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => HomeworkCard(homework: items[i]),
                ),
        ),
      ],
    );
  }

  /// Широкий режим: полоса дат сверху + колонки по дням. Сколько колонок
  /// влезет (минимум ~320 px каждая), столько и показываем; выбранный день
  /// встаёт в центр.
  Widget _buildWide(double width) {
    final byDate = _itemsByDate();
    final n = math.max(1, (width / 320).floor());
    _colsPerView = n;
    final colW = width / n;
    final selCol = _selectedColIndex();

    return Column(
      children: [
        const HomeworkGroupSwitcher(),
        _DateStrip(
          dates: _dates,
          selectedIndex: _selectedIndex,
          onSelected: _select,
          itemScrollController: _itemScrollController,
        ),
        const Divider(height: 1),
        Expanded(
          child: ScrollablePositionedList.builder(
            itemScrollController: _columnsScroll,
            scrollDirection: Axis.horizontal,
            initialScrollIndex: selCol,
            initialAlignment: _centerAlignment(),
            itemCount: _colDates.length,
            itemBuilder: (context, i) {
              final d = _colDates[i];
              return SizedBox(
                width: colW,
                child: _DayColumn(
                  date: d,
                  items: byDate[d] ?? const [],
                  selected: i == selCol,
                  showDivider: i > 0,
                  onHeaderTap: () {
                    final idx = _dates.indexOf(d);
                    if (idx >= 0) _select(idx);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Колонка одного дня: шапка (кликабельная, подсвечена у выбранного дня)
/// и вертикальный список карточек.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final weekday = kWeekdaysShort[date.weekday - 1];
    final dayMonth = '${date.day}.${date.month.toString().padLeft(2, '0')}';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: showDivider
            ? Border(left: BorderSide(color: cs.outlineVariant))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: selected ? cs.secondaryContainer : Colors.transparent,
            child: InkWell(
              onTap: onHeaderTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      '$weekday, $dayMonth',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? cs.onSecondaryContainer
                            : cs.onSurface,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? cs.onSecondaryContainer
                              : cs.primary,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      '${items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
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
