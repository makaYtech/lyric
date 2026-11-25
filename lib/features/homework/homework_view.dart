import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/layout/adaptive.dart';
import '../../core/settings/homework_prefs.dart';
import '../../core/util/date_time.dart';
import '../../core/util/labels.dart';
import '../../domain/homework/homework.dart';
import '../../widgets/common/async_state_view.dart';
import '../../widgets/homework/homework_card.dart';
import '../../widgets/homework/homework_group_switcher.dart';
import '../../widgets/common/stable_layout_builder.dart';

part './homework_view_date_strip.dart';
part './homework_view_day_column.dart';

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

  // Колонки есть только у дней с ДЗ; позиция колонки i в центре = i * colW.
  PageController? _colController;
  int _colsN = 0;
  final _focus = FocusNode(debugLabel: 'homework');
  List<DateTime> _colDates = const [];
  // Листание колесом/тачпадом: накапливаем дельту жеста и делаем ОДИН шаг.
  double _wheelAccum = 0;
  DateTime? _wheelLast;
  DateTime? _wheelStepAt;
  DateTime? _lastScrollAt;
  double _dragAccum = 0;
  Map<DateTime, List<Homework>>? _byDateCache;
  List<Homework>? _byDateCacheForList;

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

    final c = _colController;
    if (c != null && c.hasClients && _colDates.isNotEmpty) {
      // Подряд идущие шаги анимируем короче, чтобы не отставать от прокрутки.
      final now = DateTime.now();
      final last = _lastScrollAt;
      _lastScrollAt = now;
      final chained =
          last != null &&
          now.difference(last) < const Duration(milliseconds: 350);
      c.animateToPage(
        _selectedColIndex(),
        duration: Duration(milliseconds: chained ? 220 : 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Колонка выбранного дня (или ближайшего следующего с ДЗ).
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
    // Кэш «ДЗ по датам» от выбора не зависит — сбрасываем только список дня.
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
  /// Прокрутка PageView выключена: иначе Flutter двигал бы список «вживую»
  /// одновременно с нашей анимацией к центру, и экран улетал.
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
    if (last == null ||
        now.difference(last) > const Duration(milliseconds: 300) ||
        (_wheelAccum != 0 && (d > 0) != (_wheelAccum > 0))) {
      _wheelAccum = 0;
    }
    _wheelAccum += d;
    if (_wheelAccum.abs() < 40) return;

    // Не чаще одного шага в 110 мс; накопленное не теряется.
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

  /// Перетаскивание/свайп влево — следующий день, вправо — предыдущий.
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

    // Ключ = (широкий?, колонок в кадре): пересборка только при его смене.
    return StableLayoutBuilder<(bool, int)>(
      keyOf: (c) {
        final w = AdaptiveLayout.wideContent(c.maxWidth);
        return (w, w ? math.max(1, (c.maxWidth / 320).floor()) : 0);
      },
      builder: (context, constraints, key) {
        final (wide, cols) = key;

        final body = AsyncStateView(
          isLoading: widget.isLoading,
          error: widget.error,
          hasData: _dates.isNotEmpty,
          contentBuilder: (context) => wide ? _buildWide(cols) : _buildNarrow(),
        );

        return CallbackShortcuts(
          bindings: (wide && widget.isActive)
              ? _bindings
              : const <ShortcutActivator, VoidCallback>{},
          child: Focus(
            focusNode: _focus,
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

  /// Широкий режим: колонки по дням (~320 px), выбранный день в центре.
  Widget _buildWide(int n) {
    final byDate = _itemsByDate();
    final selCol = _selectedColIndex();

    final canPrev = selCol > 0;
    final canNext = selCol < _colDates.length - 1;

    // viewportFraction = 1/n держит выбранную колонку по центру и при ресайзе;
    // контроллер пересоздаём только при смене числа колонок.
    if (_colController == null || _colsN != n) {
      final old = _colController;
      if (old != null) {
        // Старый контроллер ещё привязан к PageView — освободим после кадра.
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _colsN = n;
      _colController = PageController(
        viewportFraction: 1 / n,
        initialPage: selCol,
      );
    }
    final controller = _colController!;

    // Полосы дат здесь нет: день выбирается кликом по шапке колонки.
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _dragAccum = 0,
        onHorizontalDragUpdate: (d) => _dragAccum += d.delta.dx,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Листаем только шагами; padEnds центрирует и крайние колонки.
            PageView.builder(
              key: ValueKey(n),
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              padEnds: true,
              itemCount: _colDates.length,
              itemBuilder: (context, i) {
                final d = _colDates[i];
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
