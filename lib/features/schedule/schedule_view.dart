import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/layout/adaptive.dart';
import '../../core/schedule/gap_utils.dart';
import '../../core/settings/schedule_prefs.dart';
import '../../core/util/date_time.dart';
import '../../core/util/labels.dart';
import '../../domain/attendance/attendance.dart';
import '../../domain/schedule/bells_timetable.dart';
import '../../domain/schedule/day_schedule.dart';
import '../../domain/schedule/lesson.dart';
import '../../domain/schedule/lesson_attendance.dart';
import '../../domain/schedule/lesson_grades.dart';
import '../../domain/grades/mark.dart';
import '../../domain/schedule/schedule_override.dart';
import '../../domain/grades/subject_grade.dart';
import '../../widgets/common/async_state_view.dart';
import '../../widgets/homework/homework_group_switcher.dart';
import '../../widgets/schedule/day_schedule_card.dart';
import '../../widgets/schedule/lesson_density.dart';
import '../../widgets/schedule/overrides_sheet.dart';
import '../../widgets/schedule/selection_toolbar.dart';
import '../../widgets/shell/adaptive_sheet.dart';
import '../../widgets/common/stable_layout_builder.dart';

part './schedule_view_actions.dart';
part './schedule_view_build.dart';
part './schedule_view_edit.dart';
part './schedule_view_scroll.dart';
part './schedule_view_selection.dart';
part './schedule_view_widgets.dart';

class ScheduleView extends StatefulWidget {
  final List<DaySchedule>? schedule;
  final List<Mark>? marks;
  final List<SubjectGrade>? grades;
  final List<Attendance>? attendances;
  final BellsTimetable? bells;

  /// true — вкладка расписания сейчас показана.
  final bool isActive;

  /// true — автоскролл на сегодня уже был в этом сеансе приложения.
  /// Флаг живёт в HomeController и переживает пересоздание виджета.
  final bool autoScrollAlreadyDone;

  /// Вызывается один раз, когда решено: прокрутили, сегодня нет в
  /// расписании или пользователь выключил настройку.
  final VoidCallback? onAutoScrollDone;

  final bool isLoading;
  final String? error;
  final DateTime weekStart;
  final ValueChanged<DateTime> onWeekChanged;
  final Future<void> Function() onRefresh;

  final Future<List<int>> Function(DateTime date, List<int> lessonIds)?
  onDeleteLessons;

  final Future<List<int>> Function(
    DateTime date,
    List<({int lessonId, String startTime, String endTime})> moves,
  )?
  onMoveLessons;

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
  )?
  onReorderLessons;

  const ScheduleView({
    super.key,
    required this.schedule,
    this.marks,
    this.grades,
    this.attendances,
    this.bells,
    this.isActive = true,
    this.autoScrollAlreadyDone = false,
    this.onAutoScrollDone,
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

class _ScheduleViewState extends State<ScheduleView>
    with AutomaticKeepAliveClientMixin {
  /// Сохраняем позицию скролла и выбранный день при уходе с вкладки.
  @override
  bool get wantKeepAlive => true;

  final _scrollController = ScrollController();
  final _focus = FocusNode(debugLabel: 'schedule');
  DateTime? _lastWheelNav;
  final _listKey = GlobalKey();
  final _dayKeys = <GlobalKey>[];
  int _activeDayIndex = 0;
  int? _pinnedIndex;

  LessonGradesLookup _gradesLookup = LessonGradesLookup.empty;
  LessonAttendanceLookup _attendanceLookup = LessonAttendanceLookup.empty;

  DateTime? _selectionDay;
  final Set<int> _selectedLessonIds = {};
  bool _selectionMode = false;

  Timer? _autoScrollTimer;
  double _autoScrollTargetDir = 0;

  /// setState — protected-член State, недоступный из extension-частей.
  void _setState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _gradesLookup = LessonGradesLookup.fromMarks(
      widget.marks,
      schedule: widget.schedule,
      grades: widget.grades,
    );
    _attendanceLookup = LessonAttendanceLookup.fromAttendances(
      widget.attendances,
    );
    if (widget.isActive && !widget.autoScrollAlreadyDone) _tryAutoScroll();
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
    if (!identical(oldWidget.attendances, widget.attendances)) {
      _attendanceLookup = LessonAttendanceLookup.fromAttendances(
        widget.attendances,
      );
    }
    if (widget.isActive && !widget.autoScrollAlreadyDone) _tryAutoScroll();
    if (!oldWidget.isActive && widget.isActive) {
      // Чтобы ←/→ листали недели сразу после переключения на вкладку.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // для AutomaticKeepAliveClientMixin
    return _buildPage(context);
  }
}
