part of 'schedule_view.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

extension _ScheduleSelection on _ScheduleViewState {
  void _enterSelection(DateTime dayDate, Lesson lesson) {
    final ids = <int>[];
    if (lesson.isGap) {
      if (lesson.id != null) ids.add(lesson.id!);
    } else {
      if (lesson.id != null) ids.add(lesson.id!);
      if (lesson.secondaryId != null) ids.add(lesson.secondaryId!);
    }
    if (ids.isEmpty) return;
    _setState(() {
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
      _setState(() {
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

    _setState(() {
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
    _setState(() {
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
    return injectGaps(base, bells: widget.bells, weekDayId: day.weekday);
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
}
