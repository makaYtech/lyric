import 'package:flutter/material.dart';

import '../core/util/labels.dart';
import '../models/day_schedule.dart';
import '../models/lesson_grades.dart';
import '../models/mark.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/schedule/day_schedule_card.dart';

class ScheduleView extends StatefulWidget {
  final List<DaySchedule>? schedule;
  final List<Mark>? marks;
  final bool isLoading;
  final String? error;
  final DateTime weekStart;
  final ValueChanged<DateTime> onWeekChanged;
  final Future<void> Function() onRefresh;

  const ScheduleView({
    super.key,
    required this.schedule,
    this.marks,
    required this.isLoading,
    required this.error,
    required this.weekStart,
    required this.onWeekChanged,
    required this.onRefresh,
  });

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  final _scrollController = ScrollController();
  final _listKey = GlobalKey();
  final _dayKeys = <GlobalKey>[];
  int _activeDayIndex = 0;
  int? _pinnedIndex;

  LessonGradesLookup _gradesLookup = LessonGradesLookup.empty;

  @override
  void initState() {
    super.initState();
    _gradesLookup = LessonGradesLookup.fromMarks(widget.marks);
  }

  @override
  void didUpdateWidget(covariant ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.marks, widget.marks)) {
      _gradesLookup = LessonGradesLookup.fromMarks(widget.marks);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureKeys(int count) {
    if (_dayKeys.length == count) return;
    _dayKeys
      ..clear()
      ..addAll(List.generate(count, (_) => GlobalKey()));
  }

  Future<void> _scrollToDay(int index) async {
    if (index < 0 || index >= _dayKeys.length) return;
    if (index == _activeDayIndex && _pinnedIndex == null) return;

    _pinnedIndex = index;
    setState(() => _activeDayIndex = index);

    await WidgetsBinding.instance.endOfFrame;
    final ctx = _dayKeys[index].currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }

    await Future.delayed(const Duration(milliseconds: 200));
    _pinnedIndex = null;
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
      setState(() => _activeDayIndex = target!);
    }
  }

  void _shiftWeek(int deltaWeeks) {
    final newStart = widget.weekStart.add(Duration(days: 7 * deltaWeeks));
    widget.onWeekChanged(DateTime(newStart.year, newStart.month, newStart.day));
  }

  Future<void> _pickWeek() async {
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

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule ?? const <DaySchedule>[];
    _ensureKeys(schedule.length);

    return Column(
      children: [
        _WeekSwitcher(
          weekStart: widget.weekStart,
          onPrev: () => _shiftWeek(-1),
          onNext: () => _shiftWeek(1),
          onPick: _pickWeek,
        ),
        if (schedule.isNotEmpty)
          _DayStrip(
            days: schedule,
            activeIndex: _activeDayIndex,
            onTap: _scrollToDay,
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
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: SingleChildScrollView(
                      key: _listKey,
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < schedule.length; i++) ...[
                            if (i > 0) const SizedBox(height: 20),
                            KeyedSubtree(
                              key: _dayKeys[i],
                              child: DayScheduleCard(
                                day: schedule[i],
                                grades: _gradesLookup,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekSwitcher extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _WeekSwitcher({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
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

  const _DayStrip({
    required this.days,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final d = days[i];
          final selected = i == activeIndex;
          final hasLessons = d.lessons.isNotEmpty;
          final label = '${kWeekdaysShort[d.date.weekday - 1]} ${d.date.day}';

          return ChoiceChip(
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(i),
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : (hasLessons
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant),
            ),
            selectedColor: theme.colorScheme.secondaryContainer,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outlineVariant,
            ),
          );
        },
      ),
    );
  }
}