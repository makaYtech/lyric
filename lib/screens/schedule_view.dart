import 'dart:async';

import 'package:flutter/material.dart';

import '../core/schedule/gap_utils.dart';
import '../core/settings/schedule_prefs.dart';
import '../core/util/labels.dart';
import '../models/bells_timetable.dart';
import '../models/day_schedule.dart';
import '../models/lesson.dart';
import '../models/lesson_grades.dart';
import '../models/mark.dart';
import '../models/schedule_override.dart';
import '../models/subject_grade.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/schedule/day_schedule_card.dart';
import '../widgets/schedule/overrides_sheet.dart';
import '../widgets/schedule/selection_toolbar.dart';

class ScheduleView extends StatefulWidget {
  final List<DaySchedule>? schedule;
  final List<Mark>? marks;
  final List<SubjectGrade>? grades;
  final BellsTimetable? bells;

  final bool isLoading;
  final String? error;
  final DateTime weekStart;
  final ValueChanged<DateTime> onWeekChanged;
  final Future<void> Function() onRefresh;

  final Future<List<int>> Function(DateTime date, List<int> lessonIds)?
  onDeleteLessons;

  /// Пакетный перенос уроков в конкретные времена (drop на окно).
  final Future<List<int>> Function(
      DateTime date,
      List<({int lessonId, String startTime, String endTime})> moves,
      )? onMoveLessons;

  final Future<void> Function(List<int> ids)? onRevertOverrideIds;
  final Future<void> Function(int id)? onRevertOverride;
  final Future<void> Function()? onRevertWeek;
  final Future<List<ScheduleOverride>> Function()? onLoadWeekOverrides;
  final Future<List<DaySchedule>> Function()? onLoadWeekRawLessons;
  final Set<String> daysWithOverrides;
  final Set<int> changedLessonIds;

  final Future<void> Function(DateTime date, int primaryId, int secondaryId)?
  onBreakPair;

  final Future<void> Function(DateTime date, int primaryId, int secondaryId)?
  onMakePair;

  final Future<List<int>> Function(
      DateTime date,
      List<Lesson> originalOrder,
      List<Lesson> newOrder,
      )? onReorderLessons;

  const ScheduleView({
    super.key,
    required this.schedule,
    this.marks,
    this.grades,
    this.bells,
    required this.isLoading,
    required this.error,
    required this.weekStart,
    required this.onWeekChanged,
    required this.onRefresh,
    this.onDeleteLessons,
    this.onMoveLessons,
    this.onRevertOverrideIds,
    this.onRevertOverride,
    this.onRevertWeek,
    this.onLoadWeekOverrides,
    this.onLoadWeekRawLessons,
    this.daysWithOverrides = const {},
    this.changedLessonIds = const {},
    this.onBreakPair,
    this.onMakePair,
    this.onReorderLessons,
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

  DateTime? _selectionDay;
  final Set<int> _selectedLessonIds = {};
  bool _selectionMode = false;

  Timer? _autoScrollTimer;
  static const _topEdgeZone = 200.0;
  static const _bottomEdgeInset = 140.0;
  static const _maxScrollSpeed = 14.0;
  double _autoScrollTargetDir = 0;

  @override
  void initState() {
    super.initState();
    _gradesLookup = LessonGradesLookup.fromMarks(
      widget.marks,
      schedule: widget.schedule,
      grades: widget.grades,
    );
  }

  @override
  void didUpdateWidget(covariant ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.marks, widget.marks) ||
        !identical(oldWidget.schedule, widget.schedule) ||
        !identical(oldWidget.grades, widget.grades)) {
      _gradesLookup = LessonGradesLookup.fromMarks(
        widget.marks,
        schedule: widget.schedule,
        grades: widget.grades,
      );
      if (_selectionMode) _pruneSelection();
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
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
      final next = (_scrollController.offset + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent);
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

  // ── Selection ──────────────────────────────────────────────────────────

  void _enterSelection(DateTime dayDate, Lesson lesson) {
    final ids = <int>[];
    if (lesson.isGap) {
      if (lesson.id != null) ids.add(lesson.id!);
    } else {
      if (lesson.id != null) ids.add(lesson.id!);
      if (lesson.secondaryId != null) ids.add(lesson.secondaryId!);
    }
    if (ids.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selectionDay = _dayOnly(dayDate);
      _selectedLessonIds
        ..clear()
        ..addAll(ids);
    });
  }

  void _toggle(DateTime dayDate, Lesson lesson) {
    if (lesson.isGap) {
      final id = lesson.id;
      if (id == null) return;
      if (_selectionDay == null || !_sameDay(_selectionDay!, dayDate)) {
        _enterSelection(dayDate, lesson);
        return;
      }
      setState(() {
        if (_selectedLessonIds.contains(id)) {
          _selectedLessonIds.remove(id);
        } else {
          _selectedLessonIds.add(id);
        }
        if (_selectedLessonIds.isEmpty) {
          _selectionMode = false;
          _selectionDay = null;
        }
      });
      return;
    }

    final id = lesson.id;
    if (id == null) return;

    if (_selectionDay == null || !_sameDay(_selectionDay!, dayDate)) {
      _enterSelection(dayDate, lesson);
      return;
    }

    final ids = <int>[id];
    if (lesson.secondaryId != null) ids.add(lesson.secondaryId!);

    setState(() {
      final fullySelected = ids.every(_selectedLessonIds.contains);
      if (fullySelected) {
        _selectedLessonIds.removeAll(ids);
      } else {
        _selectedLessonIds.addAll(ids);
      }
      if (_selectedLessonIds.isEmpty) {
        _selectionMode = false;
        _selectionDay = null;
      }
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    _stopAutoScroll();
    setState(() {
      _selectionMode = false;
      _selectionDay = null;
      _selectedLessonIds.clear();
    });
  }

  void _pruneSelection() {
    final schedule = widget.schedule ?? const <DaySchedule>[];
    final alive = <int>{};
    for (final d in schedule) {
      for (final l in d.lessons) {
        if (l.id != null) alive.add(l.id!);
        if (l.secondaryId != null) alive.add(l.secondaryId!);
      }
    }
    final visible = _dayWithGaps(_selectionDay ?? DateTime.now());
    for (final l in visible) {
      if (l.id != null) alive.add(l.id!);
    }
    _selectedLessonIds.removeWhere((id) => !alive.contains(id));
    if (_selectedLessonIds.isEmpty) {
      _selectionMode = false;
      _selectionDay = null;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<Lesson> _dayWithGaps(DateTime day) {
    DaySchedule? daySchedule;
    for (final d in widget.schedule ?? const <DaySchedule>[]) {
      if (_sameDay(d.date, day)) {
        daySchedule = d;
        break;
      }
    }
    if (daySchedule == null) return const [];
    final useMerge = SchedulePrefs.mergePairs.value;
    final base = useMerge
        ? mergeLessonPairs(daySchedule.lessons)
        : daySchedule.lessons;
    return injectGaps(
      base,
      bells: widget.bells,
      weekDayId: day.weekday,
    );
  }

  List<Lesson> _selectedVisibleLessons() {
    final day = _selectionDay;
    if (day == null) return const [];
    final visible = _dayWithGaps(day);
    return visible.where(_isLessonSelected).toList();
  }

  bool _isLessonSelected(Lesson l) {
    final id = l.id;
    if (id == null) return false;
    if (!_selectedLessonIds.contains(id)) return false;
    if (l.isGap) return true;
    final s = l.secondaryId;
    if (s != null && !_selectedLessonIds.contains(s)) return false;
    return true;
  }

  // ── Пары ───────────────────────────────────────────────────────────────

  bool _canBreakPair() {
    final selected = _selectedVisibleLessons();
    if (selected.length != 1) return false;
    if (selected.first.isGap) return false;
    return selected.first.isPaired;
  }

  bool _canMakePair() {
    final day = _selectionDay;
    if (day == null) return false;

    final selected = _selectedVisibleLessons();
    if (selected.length != 2) return false;

    final a = selected[0];
    final b = selected[1];
    if (a.isGap || b.isGap) return false;
    if (a.isPaired || b.isPaired) return false;
    if (a.subject != b.subject) return false;

    final aId = a.id;
    final bId = b.id;
    if (aId == null || bId == null) return false;

    final visible = _dayWithGaps(day);
    int? idxA;
    int? idxB;
    for (var i = 0; i < visible.length; i++) {
      if (_isLessonSelected(visible[i])) {
        if (idxA == null) {
          idxA = i;
        } else {
          idxB = i;
          break;
        }
      }
    }
    if (idxA == null || idxB == null) return false;
    return idxB == idxA + 1;
  }

  // ── Окна ───────────────────────────────────────────────────────────────

  bool _canRemoveGap() {
    final selected = _selectedVisibleLessons();
    return selected.length == 1 && selected.first.isGap;
  }

  Future<void> _removeSelectedGap() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Убрать окно — скоро'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Урок/пара брошены на окно. Предлагаем слоты из bells, которые
  /// целиком попадают в это окно, и пишем move-override.
  ///
  /// Логика выбора:
  ///   - одиночный урок: если слот ровно один — ставим сразу, если
  ///     больше — диалог с выбором.
  ///   - пара: ищем пары подряд идущих слотов. Если ни одной — отказ
  ///     с понятным сообщением. Если одна — ставим сразу, если больше —
  ///     диалог с выбором пары слотов.
  ///
  /// После перестановки окна пересчитываются автоматически: остатки
  /// разрывов ≤ порога (20 мин по умолчанию) окнами уже не считаются.
  Future<void> _handleDropOnGap(
      DateTime day,
      Lesson dragged,
      Lesson gap,
      ) async {
    final bells = widget.bells;
    final moveCb = widget.onMoveLessons;
    if (bells == null || moveCb == null) {
      _showSnack('Расписание звонков не загружено — не могу найти слот');
      return;
    }

    final ids = <int>[];
    if (dragged.id != null) ids.add(dragged.id!);
    if (dragged.secondaryId != null) ids.add(dragged.secondaryId!);
    if (ids.isEmpty) return;

    final slots = bells.slotsInsideInterval(
      day.weekday,
      gap.startTime,
      gap.endTime,
    );

    // ── Пара ─────────────────────────────────────────────────────────────
    if (dragged.isPaired && ids.length >= 2) {
      // Ищем пары подряд идущих слотов.
      final pairs = <({Bell a, Bell b})>[];
      for (var i = 0; i + 1 < slots.length; i++) {
        final a = slots[i];
        final b = slots[i + 1];
        final aOrd = a.studyOrdinal;
        final bOrd = b.studyOrdinal;
        if (aOrd != null && bOrd != null && bOrd == aOrd + 1) {
          pairs.add((a: a, b: b));
        }
      }

      if (pairs.isEmpty) {
        if (slots.isEmpty) {
          _showSnack(
              'Паре нужно два урока подряд — в этом окне нет слотов');
        } else if (slots.length == 1) {
          _showSnack(
              'Паре нужно два урока подряд — в этом окне только один слот');
        } else {
          _showSnack(
              'Паре нужно два подряд идущих слота — в этом окне таких нет');
        }
        return;
      }

      ({Bell a, Bell b})? chosen;
      if (pairs.length == 1) {
        chosen = pairs.first;
      } else {
        chosen = await _showSlotPairDialog(dragged, pairs);
      }
      if (chosen == null || !mounted) return;

      final moves = <({int lessonId, String startTime, String endTime})>[
        (
        lessonId: ids[0],
        startTime: chosen.a.beginTime,
        endTime: chosen.a.endTime,
        ),
        (
        lessonId: ids[1],
        startTime: chosen.b.beginTime,
        endTime: chosen.b.endTime,
        ),
      ];

      _exitSelection();
      final overrideIds = await moveCb(day, moves);
      if (!mounted) return;
      if (overrideIds.isNotEmpty) {
        _showUndoSnackbar(overrideIds, 'Пара перенесена');
      }
      return;
    }

    // ── Одиночный урок ───────────────────────────────────────────────────
    if (slots.isEmpty) {
      _showSnack('В этом окне нет слотов, куда можно поставить урок');
      return;
    }

    Bell? chosen;
    if (slots.length == 1) {
      chosen = slots.first;
    } else {
      chosen = await _showSlotDialog(dragged, slots);
    }
    if (chosen == null || !mounted) return;

    final moves = <({int lessonId, String startTime, String endTime})>[
      (
      lessonId: ids[0],
      startTime: chosen.beginTime,
      endTime: chosen.endTime,
      ),
    ];

    _exitSelection();
    final overrideIds = await moveCb(day, moves);
    if (!mounted) return;
    if (overrideIds.isNotEmpty) {
      _showUndoSnackbar(overrideIds, 'Урок перенесён');
    }
  }

  Future<Bell?> _showSlotDialog(Lesson lesson, List<Bell> slots) {
    final theme = Theme.of(context);
    return showDialog<Bell>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Куда поставить «${lesson.subject}»?'),
        children: [
          for (final slot in slots)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(slot),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${slot.beginTime} – ${slot.endTime}'
                        '${slot.studyOrdinal != null ? " · урок ${slot.studyOrdinal}" : ""}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Время берётся из расписания звонков',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<({Bell a, Bell b})?> _showSlotPairDialog(
      Lesson lesson,
      List<({Bell a, Bell b})> pairs,
      ) {
    final theme = Theme.of(context);
    return showDialog<({Bell a, Bell b})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Куда поставить пару «${lesson.subject}»?'),
        children: [
          for (final p in pairs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${p.a.beginTime} – ${p.b.endTime}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Пара займёт два подряд идущих слота',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _breakSelectedPair() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.length != 1) return;

    final lesson = selected.first;
    final primaryId = lesson.id;
    final secondaryId = lesson.secondaryId;
    if (primaryId == null || secondaryId == null) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Разъединить пару?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lesson.subject,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lesson.startTime}–${lesson.endTime}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Пара распадётся на два отдельных урока. Правку можно '
                  'откатить.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Разъединить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onBreakPair;
    if (callback == null) return;

    await callback(day, primaryId, secondaryId);
    if (!mounted) return;
    _exitSelection();
  }

  Future<void> _makeSelectedPair() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.length != 2) return;

    final a = selected[0];
    final b = selected[1];
    final aId = a.id;
    final bId = b.id;
    if (aId == null || bId == null) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Объединить в пару?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in [a, b])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${l.startTime}–${l.endTime} · ${l.subject}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Уроки будут показаны одной карточкой как пара. Правку '
                  'можно откатить.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Объединить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onMakePair;
    if (callback == null) return;

    await callback(day, aId, bId);
    if (!mounted) return;
    _exitSelection();
  }

  // ── Удаление ───────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.isEmpty) return;
    if (selected.any((l) => l.isGap)) return;

    final idsToDelete = <int>{};
    for (final l in selected) {
      if (l.id != null) idsToDelete.add(l.id!);
      if (l.secondaryId != null) idsToDelete.add(l.secondaryId!);
    }

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          selected.length == 1
              ? 'Удалить урок?'
              : 'Удалить ${selected.length} уроков?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Уроки исчезнут из расписания на этот день. Данные '
                    'с сервера не тронутся — правку можно откатить.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final l in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${l.startTime}–${l.endTime} · ${l.subject}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onDeleteLessons;
    if (callback == null) return;

    final overrideIds = await callback(day, idsToDelete.toList());
    if (!mounted) return;
    _exitSelection();

    if (overrideIds.isNotEmpty) {
      _showUndoSnackbar(
        overrideIds,
        selected.length == 1
            ? 'Урок удалён'
            : 'Удалено уроков: ${selected.length}',
      );
    }
  }

  // ── Перестановка ───────────────────────────────────────────────────────

  Future<void> _handleReorder(
      DateTime dayDate,
      List<Lesson> originalOrder,
      List<Lesson> newOrder,
      ) async {
    _stopAutoScroll();

    final callback = widget.onReorderLessons;
    if (callback == null) return;

    final ids = await callback(dayDate, originalOrder, newOrder);
    if (!mounted) return;

    if (ids.isNotEmpty) {
      _showUndoSnackbar(ids, 'Расписание изменено');
    }
  }

  // ── Undo-снакбар ───────────────────────────────────────────────────────

  void _showUndoSnackbar(List<int> overrideIds, String message) {
    final revert = widget.onRevertOverrideIds;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: revert == null
            ? null
            : SnackBarAction(
          label: 'Отменить',
          textColor: theme.colorScheme.inversePrimary,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            revert(overrideIds);
          },
        ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) messenger.hideCurrentSnackBar();
    });
  }

  // ── Модалка правок ─────────────────────────────────────────────────────

  Future<void> _showOverridesSheet() async {
    final loadOverrides = widget.onLoadWeekOverrides;
    final loadRaw = widget.onLoadWeekRawLessons;
    final revertOne = widget.onRevertOverride;
    final revertWeek = widget.onRevertWeek;
    if (loadOverrides == null || loadRaw == null) return;

    final overrides = await loadOverrides();
    final rawDays = await loadRaw();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.6, 0.95],
        expand: false,
        builder: (context, scrollController) => ScheduleOverridesSheet(
          overrides: overrides,
          rawDays: rawDays,
          onRevertOverride: revertOne ?? (_) async {},
          onRevertWeek: revertWeek ?? () async {},
          onReload: () async {
            final o = await loadOverrides();
            final r = await loadRaw();
            return (overrides: o, rawDays: r);
          },
        ),
      ),
    );
  }

  // ── Скролл ─────────────────────────────────────────────────────────────

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
    if (_selectionMode) _exitSelection();
    final newStart = widget.weekStart.add(Duration(days: 7 * deltaWeeks));
    widget.onWeekChanged(DateTime(newStart.year, newStart.month, newStart.day));
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

  @override
  Widget build(BuildContext context) {
    final schedule = widget.schedule ?? const <DaySchedule>[];
    _ensureKeys(schedule.length);

    return PopScope(
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
                onShowOverrides: widget.daysWithOverrides.isEmpty
                    ? null
                    : _showOverridesSheet,
                overridesCount: widget.daysWithOverrides.length,
              ),
              if (schedule.isNotEmpty)
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
                        NotificationListener<ScrollNotification>(
                          onNotification: _onScroll,
                          child: SingleChildScrollView(
                            key: _listKey,
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
                                      bells: widget.bells,
                                      isSelectionMode: _selectionMode,
                                      selectedLessonIds: _selectedLessonIds,
                                      changedLessonIds:
                                      widget.changedLessonIds,
                                      onLessonTap: _selectionMode
                                          ? (l) =>
                                          _toggle(schedule[i].date, l)
                                          : null,
                                      onLessonLongPress: _selectionMode
                                          ? null
                                          : (l) => _enterSelection(
                                        schedule[i].date,
                                        l,
                                      ),
                                      onLessonsReordered: (orig, next) =>
                                          _handleReorder(
                                            schedule[i].date,
                                            orig,
                                            next,
                                          ),
                                      onDropOnGap: (dragged, gap) =>
                                          _handleDropOnGap(
                                            schedule[i].date,
                                            dragged,
                                            gap,
                                          ),
                                      onDragGlobalY: _handleDragGlobalY,
                                      onDragEnd: _stopAutoScroll,
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
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: IgnorePointer(
              ignoring: !_selectionMode,
              child: AnimatedSlide(
                offset: _selectionMode ? Offset.zero : const Offset(0, 1.5),
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
    );
  }
}

// ── _WeekSwitcher ────────────────────────────────────────────────────────

class _WeekSwitcher extends StatelessWidget {
  final DateTime weekStart;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback? onShowOverrides;
  final int overridesCount;

  const _WeekSwitcher({
    required this.weekStart,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
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

// ── _DayStrip ────────────────────────────────────────────────────────────

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
          final hasOverrides = daysWithOverrides.contains(_iso(d.date));
          final label = '${kWeekdaysShort[d.date.weekday - 1]} ${d.date.day}';

          final chip = ChoiceChip(
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

          if (!hasOverrides) return chip;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              chip,
              Positioned(
                top: 4,
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