import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../core/layout/adaptive.dart';
import '../core/settings/homework_prefs.dart';
import '../core/util/date_time.dart';
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
  // Колонки — обычный ListView с фиксированной шириной элемента: позиция
  // колонки i в центре = i * colW (см. _buildWide), анимация — animateTo.
  ScrollController? _colController;
  double _colW = 1;
  final _focus = FocusNode(debugLabel: 'homework');
  List<DateTime> _colDates = const [];
  // Листание колесом/тачпадом: накапливаем дельту жеста и делаем ОДИН шаг.
  double _wheelAccum = 0;
  DateTime? _wheelLast;
  DateTime? _wheelStepAt;
  DateTime? _lastScrollAt;
  // Перетаскивание (палец, мышь, тачпад-свайп).
  double _dragAccum = 0;
  // Чтобы пересобрать центр при изменении ширины окна / числа колонок.
  (int, int)? _layoutKey;
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
    _colController?.dispose();
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
    final c = _colController;
    if (c != null && c.hasClients && _colDates.isNotEmpty) {
      // Шаги идут подряд (колесо, зажатая стрелка) — анимацию делаем короче,
      // чтобы она не отставала от прокрутки; одиночный шаг — поплавнее.
      final now = DateTime.now();
      final last = _lastScrollAt;
      _lastScrollAt = now;
      final chained =
          last != null &&
          now.difference(last) < const Duration(milliseconds: 350);
      c.animateTo(
        _selectedColIndex() * _colW,
        duration: Duration(milliseconds: chained ? 220 : 380),
        // easeOutCubic: быстрый старт и плавное замедление.
        curve: Curves.easeOutCubic,
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
    // Сбрасываем только кэш списка выбранного дня (узкий режим). Кэш «ДЗ по
    // датам» от выбора не зависит — раньше его пересчитывали на каждом шаге.
    _itemsCache = null;
    _itemsCacheForDate = null;
    _itemsCacheForList = null;
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
    const SingleActivator(LogicalKeyboardKey.home): _goToToday,
  };

  /// К сегодняшнему дню (или ближайшему следующему с ДЗ).
  void _goToToday() {
    if (_dates.isEmpty) return;
    final today = dayOnly(DateTime.now());
    var idx = _dates.indexWhere((d) => !d.isBefore(today));
    if (idx < 0) idx = _dates.length - 1;
    if (idx == _selectedIndex) {
      _scrollToSelected();
    } else {
      _select(idx);
    }
  }

  /// Горизонтальное колесо / тачпад / Shift+колесо — ОДИН шаг на жест.
  ///
  /// Сама прокрутка списка колонок выключена (NeverScrollableScrollPhysics),
  /// иначе Flutter двигал бы список «вживую» и одновременно запускалась наша
  /// анимация к центру — они конфликтовали, и экран улетал. Вертикальное
  /// колесо остаётся за прокруткой карточек внутри колонок.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final dx = e.scrollDelta.dx;
    final dy = e.scrollDelta.dy;
    final d = shift ? dy : dx;
    if (!shift && dx.abs() <= dy.abs()) return;

    final now = DateTime.now();
    final last = _wheelLast;
    _wheelLast = now;
    // Долгая пауза или смена направления — копим заново.
    if (last == null ||
        now.difference(last) > const Duration(milliseconds: 300) ||
        (_wheelAccum != 0 && (d > 0) != (_wheelAccum > 0))) {
      _wheelAccum = 0;
    }
    _wheelAccum += d;
    if (_wheelAccum.abs() < 40) return;

    // Не чаще одного шага в 110 мс; накопленное не теряется — следующее
    // событие сделает шаг. Так можно крутить колесо непрерывно и не ждать,
    // пока долистает до предыдущего дня.
    final stepAt = _wheelStepAt;
    if (stepAt != null &&
        now.difference(stepAt) < const Duration(milliseconds: 110)) {
      return;
    }
    _wheelStepAt = now;
    final dir = _wheelAccum > 0 ? 1 : -1;
    _wheelAccum = 0;
    _moveSelection(dir);
  }

  /// Перетаскивание влево — следующий день, вправо — предыдущий. Работает для
  /// сенсорного экрана, мыши и свайпа двумя пальцами по тачпаду.
  void _onHorizontalDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    final byDistance = _dragAccum.abs() > 60;
    final byFling = v.abs() > 500;
    if (!byDistance && !byFling) return;
    final leftward = byDistance ? _dragAccum < 0 : v < 0;
    _moveSelection(leftward ? 1 : -1);
  }

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
    final colW = width / n;
    final selCol = _selectedColIndex();
    _colW = colW;

    final canPrev = selCol > 0;
    final canNext = selCol < _colDates.length - 1;

    // Контроллер создаём сразу с нужным смещением — без «мигания» с нуля.
    final controller = _colController ??= ScrollController(
      initialScrollOffset: selCol * colW,
    );

    // Ширина окна или число колонок изменились (в т.ч. при раскрытии боковой
    // панели): колонка выбранного дня остаётся по центру. Один раз после
    // кадра, а не на каждом шаге анимации.
    final layoutKey = (n, width.round());
    if (_layoutKey != null && _layoutKey != layoutKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) {
          controller.jumpTo(_selectedColIndex() * _colW);
        }
      });
    }
    _layoutKey = layoutKey;

    // Полосы дат здесь нет: выбор дня — клик по шапке колонки. Листать можно
    // стрелками ←/→, кнопками по краям, колесом/тачпадом и свайпом;
    // Home — к сегодняшнему дню. Переключатель группировки ДЗ переехал в
    // боковую панель.
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _dragAccum = 0,
        onHorizontalDragUpdate: (d) => _dragAccum += d.delta.dx,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Листаем только шагами (клавиши, кнопки, колесо, свайп): так
            // выбранный день всегда в центре. Отступы по краям — (ширина −
            // колонка) / 2: без них первую и последнюю колонки (а
            // сегодняшний день часто у края) нельзя поставить в центр.
            ListView.builder(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: (width - colW) / 2),
              itemExtent: colW,
              itemCount: _colDates.length,
              itemBuilder: (context, i) {
                final d = _colDates[i];
                // RepaintBoundary: при листании колонки сдвигаются готовыми
                // слоями, а не перерисовываются каждый кадр (карточки с
                // тенями — дорогие).
                return RepaintBoundary(
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
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _EdgeButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Предыдущий день (←)',
                  onPressed: canPrev ? () => _moveSelection(-1) : null,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _EdgeButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Следующий день (→)',
                  onPressed: canNext ? () => _moveSelection(1) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Колонка одного дня: шапка (кликабельная, подсвечена у выбранного дня)
/// и вертикальный список карточек. Сегодняшний день выделен отдельно от
/// выбранного: цветная полоса сверху, плашка «сегодня», лёгкий тон колонки.
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
          // Цветная полоса сегодняшнего дня.
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
