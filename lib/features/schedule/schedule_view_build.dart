part of 'schedule_view.dart';

const _diaryTopPadding = 12.0;
// Снизу оставляем место под плавающую панель выбора уроков.
const _diaryBottomPadding = 64.0;

extension _ScheduleBuild on _ScheduleViewState {
  Widget _dayCard(
    List<DaySchedule> schedule,
    int i, [
    LessonDensity density = LessonDensity.comfortable,
  ]) {
    return KeyedSubtree(
      key: _dayKeys[i],
      child: DayScheduleCard(
        density: density,
        day: schedule[i],
        grades: _gradesLookup,
        attendances: _attendanceLookup,
        bells: widget.bells,
        isSelectionMode: _selectionMode,
        selectedLessonIds: _selectedLessonIds,
        changedLessonIds: widget.changedLessonIds,
        onLessonTap: _selectionMode
            ? (l) => _toggle(schedule[i].date, l)
            : null,
        onLessonLongPress: _selectionMode
            ? null
            : (l) => _enterSelection(schedule[i].date, l),
        onLessonsReordered: (orig, next) =>
            _handleReorder(schedule[i].date, orig, next),
        onDropOnGap: (dragged, gap) =>
            _handleDropOnGap(schedule[i].date, dragged, gap),
        onDragGlobalY: _handleDragGlobalY,
        onDragEnd: _stopAutoScroll,
      ),
    );
  }

  /// Тело вкладки: узкое окно — один список дней, широкое — «дневник».
  Widget _buildScrollBody(List<DaySchedule> schedule, bool wide) {
    if (!wide) {
      return _scrollBody(schedule, wide: false);
    }
    return StableLayoutBuilder<LessonDensity>(
      keyOf: (c) => _pickDensity(schedule, c.maxHeight),
      builder: (context, _, density) =>
          _scrollBody(schedule, wide: true, density: density),
    );
  }

  /// Индексы дней для левой (пн–ср) и правой (чт–сб) страницы «дневника».
  (List<int>, List<int>) _diaryPages(List<DaySchedule> schedule) {
    final left = <int>[];
    final right = <int>[];
    for (var i = 0; i < schedule.length; i++) {
      (schedule[i].date.weekday <= DateTime.wednesday ? left : right).add(i);
    }
    return (left, right);
  }

  /// Самая свободная плотность, при которой более высокая страница влезает
  /// в [viewportHeight]. Иначе — dense с прокруткой.
  LessonDensity _pickDensity(
    List<DaySchedule> schedule,
    double viewportHeight,
  ) {
    final (left, right) = _diaryPages(schedule);
    final avail = viewportHeight - _diaryTopPadding - _diaryBottomPadding;

    double pageHeight(List<int> idx, LessonDensity d) {
      var h = 0.0;
      for (final i in idx) {
        final n = schedule[i].lessons.length;
        // +1 — возможное «окно» между уроками.
        final rows = n == 0 ? 1 : n + 1;
        h += d.estDayOverhead + rows * d.estRow;
      }
      return h;
    }

    for (final d in LessonDensity.values) {
      final h = pageHeight(left, d) > pageHeight(right, d)
          ? pageHeight(left, d)
          : pageHeight(right, d);
      if (h <= avail) return d;
    }
    return LessonDensity.dense;
  }

  Widget _scrollBody(
    List<DaySchedule> schedule, {
    required bool wide,
    LessonDensity density = LessonDensity.comfortable,
  }) {
    final scroll = SingleChildScrollView(
      key: _listKey,
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: wide
          ? const EdgeInsets.fromLTRB(
              16,
              _diaryTopPadding,
              16,
              _diaryBottomPadding,
            )
          : const EdgeInsets.fromLTRB(16, 16, 16, 96),
      child: wide
          ? _buildDiary(schedule, density)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < schedule.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  _dayCard(schedule, i),
                ],
              ],
            ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: wide
          ? Listener(
              onPointerSignal: _onPointerSignal,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: scroll,
              ),
            )
          : scroll,
    );
  }

  Widget _buildDiary(List<DaySchedule> schedule, LessonDensity density) {
    final (left, right) = _diaryPages(schedule);
    final dayGap = switch (density) {
      LessonDensity.comfortable => 16.0,
      LessonDensity.compact => 12.0,
      LessonDensity.dense => 8.0,
    };

    Widget page(List<int> indexes) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var k = 0; k < indexes.length; k++) ...[
          if (k > 0) SizedBox(height: dayGap),
          _dayCard(schedule, indexes[k], density),
        ],
      ],
    );

    final spine = Theme.of(context).colorScheme.outlineVariant;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: page(left)),
                const SizedBox(width: 32),
                Expanded(child: page(right)),
              ],
            ),
            // «Корешок» дневника по центру разворота.
            Positioned.fill(
              child: Center(
                child: VerticalDivider(width: 1, thickness: 1, color: spine),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final schedule = widget.schedule ?? const <DaySchedule>[];
    _ensureKeys(schedule.length);

    return StableLayoutBuilder<bool>(
      keyOf: (c) => AdaptiveLayout.wideContent(c.maxWidth),
      builder: (context, constraints, wide) {
        return CallbackShortcuts(
          bindings: (wide && widget.isActive)
              ? _bindings
              : const <ShortcutActivator, VoidCallback>{},
          child: Focus(
            focusNode: _focus,
            child: PopScope(
              canPop: !_selectionMode,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && _selectionMode) _exitSelection();
              },
              child: Stack(
                children: [
                  Column(
                    children: [
                      _WeekSwitcher(
                        weekStart: widget.weekStart,
                        onPrev: () => _shiftWeek(-1),
                        onNext: () => _shiftWeek(1),
                        onPick: _pickWeek,
                        onToday: isSameDay(widget.weekStart, currentMonday())
                            ? null
                            : _goToCurrentWeek,
                        onShowOverrides: widget.daysWithOverrides.isEmpty
                            ? null
                            : _showOverridesSheet,
                        overridesCount: widget.daysWithOverrides.length,
                      ),
                      // На широком экране ДЗ группируются в боковой панели.
                      if (!wide) const HomeworkGroupSwitcher(),
                      if (schedule.isNotEmpty && !wide)
                        _DayStrip(
                          days: schedule,
                          activeIndex: _activeDayIndex,
                          onTap: _scrollToDay,
                          daysWithOverrides: widget.daysWithOverrides,
                        ),
                      const Divider(height: 1),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: widget.onRefresh,
                          child: AsyncStateView(
                            isLoading: widget.isLoading,
                            error: widget.error,
                            hasData: schedule.isNotEmpty,
                            contentBuilder: (context) =>
                                _buildScrollBody(schedule, wide),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: IgnorePointer(
                      ignoring: !_selectionMode,
                      child: AnimatedSlide(
                        offset: _selectionMode
                            ? Offset.zero
                            : const Offset(0, 1.5),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          opacity: _selectionMode ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Center(
                            child: ScheduleSelectionToolbar(
                              selectedCount: _selectedVisibleLessons().length,
                              actions: [
                                if (_canRemoveGap())
                                  IconButton(
                                    onPressed: _removeSelectedGap,
                                    icon: const Icon(Icons.compress),
                                    tooltip: 'Убрать окно',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                  ),
                                if (_canBreakPair())
                                  IconButton(
                                    onPressed: _breakSelectedPair,
                                    icon: const Icon(Icons.call_split),
                                    tooltip: 'Разъединить пару',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                  ),
                                if (_canMakePair())
                                  IconButton(
                                    onPressed: _makeSelectedPair,
                                    icon: const Icon(Icons.merge),
                                    tooltip: 'Объединить в пару',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                  ),
                                IconButton(
                                  onPressed: _confirmDelete,
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Удалить уроки',
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ],
                              onCancel: _exitSelection,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
