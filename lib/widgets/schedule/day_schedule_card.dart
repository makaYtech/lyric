import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/schedule/gap_utils.dart';
import '../../core/settings/schedule_prefs.dart';
import '../../models/bells_timetable.dart';
import '../../models/day_schedule.dart';
import '../../models/lesson.dart';
import '../../models/lesson_attendance.dart';
import '../../models/lesson_grades.dart';
import 'gap_card.dart';
import 'lesson_card.dart';

class DayScheduleCard extends StatefulWidget {
  final DaySchedule day;
  final bool highlightToday;
  final LessonGradesLookup grades;
  final LessonAttendanceLookup attendances;
  final BellsTimetable? bells;

  final bool isSelectionMode;
  final Set<int> selectedLessonIds;
  final Set<int> changedLessonIds;

  final void Function(Lesson lesson)? onLessonTap;
  final void Function(Lesson lesson)? onLessonLongPress;

  final void Function(List<Lesson> originalOrder, List<Lesson> newOrder)?
  onLessonsReordered;

  /// Урок/пара брошены на окно. ScheduleView откроет диалог со слотами.
  final void Function(Lesson dragged, Lesson gap)? onDropOnGap;

  final void Function(double globalY)? onDragGlobalY;
  final VoidCallback? onDragEnd;

  const DayScheduleCard({
    super.key,
    required this.day,
    this.highlightToday = true,
    this.grades = LessonGradesLookup.empty,
    this.attendances = LessonAttendanceLookup.empty,
    this.bells,
    this.isSelectionMode = false,
    this.selectedLessonIds = const {},
    this.changedLessonIds = const {},
    this.onLessonTap,
    this.onLessonLongPress,
    this.onLessonsReordered,
    this.onDropOnGap,
    this.onDragGlobalY,
    this.onDragEnd,
  });

  @override
  State<DayScheduleCard> createState() => _DayScheduleCardState();
}

class _DayScheduleCardState extends State<DayScheduleCard> {
  List<Lesson>? _mergedCache;
  List<Lesson>? _mergedFor;

  final _contentKey = GlobalKey();
  final _lessonKeys = <int, GlobalKey>{};
  GlobalKey _keyFor(int id) => _lessonKeys.putIfAbsent(id, () => GlobalKey());

  List<Lesson>? _dragOrder;
  int? _dragLessonId;
  double? _dragGhostCenterContent;
  List<double>? _slotTops;
  List<double>? _slotHeights;
  int? _dragTargetIndex;

  List<Lesson>? _pendingOrder;
  bool _suppressAnimation = false;
  Timer? _pendingOrderTimer;

  bool get _isDragging => _dragLessonId != null && _dragOrder != null;

  @override
  void didUpdateWidget(covariant DayScheduleCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isDragging && !identical(oldWidget.day.lessons, widget.day.lessons)) {
      _resetDragState();
    }

    if (!identical(oldWidget.day.lessons, widget.day.lessons) &&
        _pendingOrder != null) {
      _pendingOrder = null;
      _pendingOrderTimer?.cancel();
      _pendingOrderTimer = null;
    }

    if (!identical(oldWidget.day.lessons, widget.day.lessons)) {
      final aliveIds = <int>{};
      for (final l in widget.day.lessons) {
        for (final id in _idsOf(l)) {
          aliveIds.add(id);
        }
      }
      _lessonKeys.removeWhere((id, _) => !aliveIds.contains(id));
    }
  }

  @override
  void dispose() {
    _pendingOrderTimer?.cancel();
    super.dispose();
  }

  List<Lesson> _merged() {
    if (identical(_mergedFor, widget.day.lessons) && _mergedCache != null) {
      return _mergedCache!;
    }
    _mergedCache = mergeLessonPairs(widget.day.lessons);
    _mergedFor = widget.day.lessons;
    return _mergedCache!;
  }

  List<Lesson> _visibleWithGaps() {
    if (_pendingOrder != null) return _pendingOrder!;
    final merged = SchedulePrefs.mergePairs.value
        ? _merged()
        : widget.day.lessons;
    return injectGaps(
      merged,
      bells: widget.bells,
      weekDayId: widget.day.date.weekday,
    );
  }

  Iterable<int> _idsOf(Lesson l) sync* {
    if (l.id != null) yield l.id!;
    if (l.secondaryId != null) yield l.secondaryId!;
  }

  int _visibleSelectedCountInDay() {
    final merged = SchedulePrefs.mergePairs.value
        ? _merged()
        : widget.day.lessons;
    var count = 0;
    for (final l in merged) {
      final ids = _idsOf(l).toList();
      if (ids.isEmpty) continue;
      if (ids.every(widget.selectedLessonIds.contains)) count++;
    }
    return count;
  }

  List<Lesson> _expandToRaw(List<Lesson> visible) {
    final pool = <int, Lesson>{};
    for (final l in widget.day.lessons) {
      if (l.id != null) pool[l.id!] = l;
    }
    final out = <Lesson>[];
    for (final v in visible) {
      for (final id in _idsOf(v)) {
        final r = pool[id];
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  // ── Gesture ────────────────────────────────────────────────────────────

  void _onLongPressStart(Lesson lesson, LongPressStartDetails details) {
    if (_isDragging) _resetDragState();
    if (!widget.isSelectionMode) return;
    if (lesson.isGap) return;
    if (_visibleSelectedCountInDay() != 1) return;
    if (!_idsOf(lesson).every(widget.selectedLessonIds.contains)) return;
    if (lesson.id == null) return;

    _startDrag(lesson, details.globalPosition);
  }

  void _startDrag(Lesson lesson, Offset globalPos) {
    try {
      final contentBox =
          _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (contentBox == null) return;
      final contentTop = contentBox.localToGlobal(Offset.zero).dy;

      final lessons = _visibleWithGaps();
      final tops = <double>[];
      final heights = <double>[];
      for (final l in lessons) {
        final key = l.id == null ? null : _lessonKeys[l.id!];
        final box = key?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        tops.add(box.localToGlobal(Offset.zero).dy - contentTop);
        heights.add(box.size.height);
      }

      final origIndex = lessons.indexWhere((l) => l.id == lesson.id);
      if (origIndex < 0) return;

      setState(() {
        _dragOrder = lessons;
        _dragLessonId = lesson.id;
        _dragGhostCenterContent = globalPos.dy - contentTop;
        _slotTops = tops;
        _slotHeights = heights;
        _dragTargetIndex = origIndex;
      });
    } catch (e, st) {
      debugPrint('DayScheduleCard._startDrag failed: $e\n$st');
    }
  }

  void _onLongPressMoveUpdate(
    int lessonId,
    LongPressMoveUpdateDetails details,
  ) {
    if (!_isDragging) return;
    if (_dragLessonId != lessonId) return;
    final tops = _slotTops;
    final heights = _slotHeights;
    if (tops == null || heights == null) return;

    final contentBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (contentBox == null) return;
    final contentTop = contentBox.localToGlobal(Offset.zero).dy;

    final ghostCenterContent = details.globalPosition.dy - contentTop;

    final dragIndex = _dragOrder!.indexWhere((l) => l.id == _dragLessonId);
    if (dragIndex < 0) return;

    var target = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < tops.length; i++) {
      final center = tops[i] + heights[i] / 2;
      final d = (center - ghostCenterContent).abs();
      if (d < bestDist) {
        bestDist = d;
        target = i;
      }
    }

    setState(() {
      _dragGhostCenterContent = ghostCenterContent;
      _dragTargetIndex = target;
    });

    widget.onDragGlobalY?.call(details.globalPosition.dy);
  }

  void _onLongPressEnd(int lessonId, LongPressEndDetails details) {
    if (!_isDragging) return;
    if (_dragLessonId != lessonId) {
      _resetDragState();
      widget.onDragEnd?.call();
      return;
    }

    final origOrder = _dragOrder!;
    final dragIndex = origOrder.indexWhere((l) => l.id == _dragLessonId);
    final targetIndex = _dragTargetIndex;
    if (dragIndex < 0 || targetIndex == null) {
      _resetDragState();
      widget.onDragEnd?.call();
      return;
    }

    widget.onDragEnd?.call();

    final dragged = origOrder[dragIndex];
    final target = origOrder[targetIndex];

    // Drop на окно — отдаём наружу, там откроется диалог со слотами.
    // Только для drag'а обычного урока/пары, не окна.
    if (target.isGap && !dragged.isGap && widget.onDropOnGap != null) {
      _resetDragState();
      widget.onDropOnGap!(dragged, target);
      return;
    }

    if (dragIndex == targetIndex) {
      _resetDragState();
      return;
    }

    final without = <Lesson>[...origOrder]..removeAt(dragIndex);
    without.insert(targetIndex, origOrder[dragIndex]);

    setState(() {
      _dragOrder = null;
      _dragLessonId = null;
      _dragGhostCenterContent = null;
      _slotTops = null;
      _slotHeights = null;
      _dragTargetIndex = null;

      _pendingOrder = without;
      _suppressAnimation = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _suppressAnimation = false);
    });

    _pendingOrderTimer?.cancel();
    _pendingOrderTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _pendingOrder != null) {
        setState(() => _pendingOrder = null);
      }
    });

    widget.onLessonsReordered?.call(
      _expandToRaw(origOrder),
      _expandToRaw(without),
    );
  }

  void _resetDragState() {
    if (!mounted) return;
    setState(() {
      _dragOrder = null;
      _dragLessonId = null;
      _dragGhostCenterContent = null;
      _slotTops = null;
      _slotHeights = null;
      _dragTargetIndex = null;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = widget.day;
    final isToday = widget.highlightToday && _isToday(day.date);

    final todayTint = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.10),
      theme.colorScheme.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                day.weekdayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isToday ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                day.dateLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'сегодня',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Card(
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          color: isToday ? todayTint : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ValueListenableBuilder<bool>(
              valueListenable: SchedulePrefs.mergePairs,
              builder: (context, merge, _) => ValueListenableBuilder<bool>(
                valueListenable: SchedulePrefs.showGaps,
                builder: (context, _, _) => ValueListenableBuilder<int>(
                  valueListenable: SchedulePrefs.gapThresholdMinutes,
                  builder: (context, _, _) {
                    final lessons = merge ? _merged() : day.lessons;
                    return _buildContent(
                      injectGaps(
                        lessons,
                        bells: widget.bells,
                        weekDayId: day.date.weekday,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(List<Lesson> lessons) {
    if (lessons.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Нет расписания',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final displayOrder =
        _pendingOrder ??
        ([...lessons]..sort((a, b) => a.startTime.compareTo(b.startTime)));

    return Stack(
      key: _contentKey,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < displayOrder.length; i++)
              _buildSlot(displayOrder, i),
          ],
        ),
        if (_isDragging) _buildDragGhost(displayOrder),
      ],
    );
  }

  Widget _buildSlot(List<Lesson> order, int index) {
    final lesson = order[index];
    final key = lesson.id == null ? null : _keyFor(lesson.id!);
    final shifted = _computeShift(order, index);
    final isDragged = _isDragging && lesson.id == _dragLessonId;

    final isSelected = _idsOf(lesson).every(widget.selectedLessonIds.contains);

    if (lesson.isGap) {
      final isDropTarget = _isDragging && _dragTargetIndex == index;
      return KeyedSubtree(
        key: key,
        child: GapCard(
          gap: lesson,
          isSelectionMode: widget.isSelectionMode,
          isSelected: isSelected,
          highlighted: isDropTarget,
          onTap: widget.isSelectionMode
              ? () => widget.onLessonTap?.call(lesson)
              : null,
        ),
      );
    }

    final VoidCallback? tapCb;
    if (widget.isSelectionMode && !_isDragging) {
      tapCb = () => widget.onLessonTap?.call(lesson);
    } else if (widget.isSelectionMode) {
      tapCb = () {};
    } else {
      tapCb = null;
    }

    final VoidCallback? longPressCb;
    if (!widget.isSelectionMode) {
      longPressCb = () => widget.onLessonLongPress?.call(lesson);
    } else {
      longPressCb = null;
    }

    final canDrag =
        widget.isSelectionMode &&
        _visibleSelectedCountInDay() == 1 &&
        _idsOf(lesson).every(widget.selectedLessonIds.contains) &&
        lesson.id != null;

    final isChanged = _idsOf(lesson).any(widget.changedLessonIds.contains);

    Widget child = LessonCard(
      lesson: lesson,
      grades: widget.grades.forLesson(lesson),
      attendance: widget.attendances.forLesson(lesson),
      isSelectionMode: widget.isSelectionMode,
      selectedLessonIds: widget.selectedLessonIds,
      onTap: tapCb,
      onLongPress: longPressCb,
      invisible: isDragged,
      disableInkWell: canDrag,
      changed: isChanged,
    );

    if (canDrag) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_isDragging) widget.onLessonTap?.call(lesson);
        },
        onLongPressStart: (d) => _onLongPressStart(lesson, d),
        onLongPressMoveUpdate: (d) => _onLongPressMoveUpdate(lesson.id!, d),
        onLongPressEnd: (d) => _onLongPressEnd(lesson.id!, d),
        child: child,
      );
    }

    return KeyedSubtree(
      key: key,
      child: AnimatedContainer(
        duration: _suppressAnimation
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, shifted, 0),
        child: child,
      ),
    );
  }

  double _computeShift(List<Lesson> order, int index) {
    if (!_isDragging) return 0;
    final target = _dragTargetIndex;
    final heights = _slotHeights;
    if (target == null || heights == null) return 0;
    if (index >= heights.length) return 0;
    if (target >= heights.length) return 0;

    final dragIndex = order.indexWhere((l) => l.id == _dragLessonId);
    if (dragIndex < 0 || dragIndex >= heights.length) return 0;
    if (index == dragIndex) return 0;

    final hd = heights[dragIndex];
    if (dragIndex < target) {
      if (index > dragIndex && index <= target) return -hd;
    } else {
      if (index >= target && index < dragIndex) return hd;
    }
    return 0;
  }

  double _snapTopForDraggedItem(List<Lesson> order, int dragIndex, int target) {
    final heights = _slotHeights;
    if (heights == null) return 0;
    final n = order.length;
    if (dragIndex < 0 || dragIndex >= n) return 0;
    if (target < 0 || target >= n) return 0;
    if (heights.length != n) return 0;

    final indices = List<int>.generate(n, (i) => i);
    indices.removeAt(dragIndex);
    indices.insert(target, dragIndex);
    var top = 0.0;
    for (var i = 0; i < target; i++) {
      top += heights[indices[i]];
    }
    return top;
  }

  Widget _buildDragGhost(List<Lesson> order) {
    final tops = _slotTops;
    final heights = _slotHeights;
    final target = _dragTargetIndex;
    final ghostCenter = _dragGhostCenterContent;
    if (tops == null ||
        heights == null ||
        target == null ||
        ghostCenter == null) {
      return const SizedBox.shrink();
    }
    final dragIndex = order.indexWhere((l) => l.id == _dragLessonId);
    if (dragIndex < 0 || dragIndex >= heights.length) {
      return const SizedBox.shrink();
    }

    final lesson = order[dragIndex];
    final rawTop = ghostCenter - heights[dragIndex] / 2;
    final snapTop = _snapTopForDraggedItem(order, dragIndex, target);
    final top = rawTop * 0.75 + snapTop * 0.25;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        builder: (context, t, child) => Transform.scale(
          scale: 0.95 + 0.05 * t,
          child: Opacity(opacity: t, child: child),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LessonCard(
            lesson: lesson,
            grades: widget.grades.forLesson(lesson),
            attendance: widget.attendances.forLesson(lesson),
            isSelectionMode: false,
            selectedLessonIds: const {},
            onTap: () {},
          ),
        ),
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
