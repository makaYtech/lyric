part of 'schedule_view.dart';

const _topEdgeZone = 200.0;
const _bottomEdgeInset = 140.0;
const _maxScrollSpeed = 14.0;

extension _ScheduleScroll on _ScheduleViewState {
  void _tryAutoScroll() {
    if (widget.autoScrollAlreadyDone) return;

    if (!SchedulePrefs.autoScrollToToday.value) {
      widget.onAutoScrollDone?.call();
      return;
    }

    final schedule = widget.schedule;
    // Данных ещё нет — попробуем на следующем апдейте, флаг НЕ выставляем.
    if (schedule == null || schedule.isEmpty) return;

    final now = DateTime.now();
    final targetIndex = schedule.indexWhere(
      (d) =>
          d.date.year == now.year &&
          d.date.month == now.month &&
          d.date.day == now.day,
    );

    // Данные есть — фиксируем «решено», даже если сегодня нет в расписании.
    widget.onAutoScrollDone?.call();

    if (targetIndex < 0) return;
    if (targetIndex == _activeDayIndex && _pinnedIndex == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToDay(targetIndex);
    });
  }

  void _handleDragGlobalY(double globalY) {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final bottomEdge = size.height - _bottomEdgeInset;

    double dir = 0;
    if (globalY < _topEdgeZone) {
      dir = -(1 - (globalY / _topEdgeZone)).clamp(0.0, 1.0);
    } else if (globalY > bottomEdge) {
      final denom = (size.height - bottomEdge).clamp(1.0, 1000.0);
      dir = ((globalY - bottomEdge) / denom).clamp(0.0, 1.0);
    }

    if (dir == 0) {
      _stopAutoScroll();
      return;
    }
    _startAutoScroll(dir);
  }

  void _startAutoScroll(double dir) {
    if (_autoScrollTimer != null) {
      _autoScrollTargetDir = dir;
      return;
    }
    _autoScrollTargetDir = dir;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final delta = _autoScrollTargetDir * _maxScrollSpeed;
      final next = (_scrollController.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != _scrollController.offset) {
        _scrollController.jumpTo(next);
      }
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollTargetDir = 0;
  }

  void _ensureKeys(int count) {
    if (_dayKeys.length == count) return;
    _dayKeys
      ..clear()
      ..addAll(List.generate(count, (_) => GlobalKey()));
  }

  /// Пролистывает к дню [index] внутри внутреннего списка.
  ///
  /// ВАЖНО: не Scrollable.ensureVisible — он двигает все Scrollable-предки,
  /// включая внешний PageView, из-за чего вкладка «перекидывалась».
  Future<void> _scrollToDay(int index) async {
    if (index < 0 || index >= _dayKeys.length) return;
    if (index == _activeDayIndex && _pinnedIndex == null) return;

    _pinnedIndex = index;
    _setState(() => _activeDayIndex = index);

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_scrollController.hasClients) {
      _pinnedIndex = null;
      return;
    }

    final dayCtx = _dayKeys[index].currentContext;
    final listCtx = _listKey.currentContext;
    if (dayCtx == null || listCtx == null) {
      _pinnedIndex = null;
      return;
    }

    final dayBox = dayCtx.findRenderObject() as RenderBox?;
    final listBox = listCtx.findRenderObject() as RenderBox?;
    if (dayBox == null || listBox == null) {
      _pinnedIndex = null;
      return;
    }

    final dayTop = dayBox.localToGlobal(Offset.zero).dy;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final delta = dayTop - listTop;

    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) _pinnedIndex = null;
  }

  bool _onScroll(ScrollNotification notification) {
    if (_pinnedIndex != null) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _updateActiveDayFromScroll();
    }
    return false;
  }

  void _updateActiveDayFromScroll() {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final listTop = listBox.localToGlobal(Offset.zero).dy;
    final anchor = listTop + 80;

    int? target;

    for (var i = 0; i < _dayKeys.length; i++) {
      final ctx = _dayKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;

      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;

      if (top <= anchor && bottom > anchor) {
        target = i;
        break;
      }
    }

    target ??= () {
      int? last;
      for (var i = 0; i < _dayKeys.length; i++) {
        final ctx = _dayKeys[i].currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        if (top <= anchor) last = i;
      }
      return last;
    }();

    target ??= 0;

    if (target != _activeDayIndex) {
      _setState(() => _activeDayIndex = target!);
    }
  }

  void _shiftWeek(int deltaWeeks) {
    if (_selectionMode) _exitSelection();
    final newStart = widget.weekStart.add(Duration(days: 7 * deltaWeeks));
    widget.onWeekChanged(DateTime(newStart.year, newStart.month, newStart.day));
  }

  void _goToCurrentWeek() {
    if (_selectionMode) _exitSelection();
    widget.onWeekChanged(currentMonday());
  }

  Map<ShortcutActivator, VoidCallback> get _bindings => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shiftWeek(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shiftWeek(1),
    const SingleActivator(LogicalKeyboardKey.home): _goToCurrentWeek,
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (_selectionMode) _exitSelection();
    },
  };

  /// Горизонтальное колесо / тачпад / Shift+колесо листает недели.
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final dx = e.scrollDelta.dx;
    final dy = e.scrollDelta.dy;
    final d = shift ? dy : dx;
    if (d.abs() < 4) return;
    if (!shift && dx.abs() <= dy.abs()) return;

    final now = DateTime.now();
    final last = _lastWheelNav;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastWheelNav = now;
    _shiftWeek(d > 0 ? 1 : -1);
  }

  Future<void> _pickWeek() async {
    if (_selectionMode) _exitSelection();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.weekStart,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: 'Выберите любой день нужной недели',
    );
    if (picked == null) return;
    final monday = picked.subtract(Duration(days: picked.weekday - 1));
    widget.onWeekChanged(DateTime(monday.year, monday.month, monday.day));
  }
}
