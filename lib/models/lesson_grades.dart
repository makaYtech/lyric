import 'day_schedule.dart';
import 'lesson.dart';
import 'mark.dart';
import 'subject_grade.dart';

/// Одна оценка на уроке — значение, когда получили и (опционально)
/// тип работы. isAbsence — «Н» (отсутствовал), value в этом случае 0.
class LessonGrade {
  final int value;
  final DateTime? receivedAt;
  final String? workType;
  final bool isAbsence;

  const LessonGrade(
      this.value,
      this.receivedAt, {
        this.workType,
        this.isAbsence = false,
      });
}

/// Быстрый поиск оценок по id урока из schedule_items
/// (Mark.scheduleLessonId == Lesson.id).
/// У пары уроков (mergeLessonPairs) secondaryId — id второго урока,
/// поэтому его оценки тоже подтягиваются.
class LessonGradesLookup {
  final Map<int, List<LessonGrade>> _byLessonId;

  const LessonGradesLookup._(this._byLessonId);

  static const empty = LessonGradesLookup._({});

  factory LessonGradesLookup.fromMarks(
      List<Mark>? marks, {
        List<DaySchedule>? schedule,
        List<SubjectGrade>? grades,
      }) {
    if (marks == null || marks.isEmpty) return empty;

    final lessonSubject = <int, String>{};
    if (schedule != null) {
      for (final day in schedule) {
        for (final l in day.lessons) {
          if (l.id != null) lessonSubject[l.id!] = l.subject;
        }
      }
    }

    final subjectByName = <String, SubjectGrade>{};
    if (grades != null) {
      for (final g in grades) subjectByName[g.name] = g;
    }

    final map = <int, List<LessonGrade>>{};
    for (final m in marks) {
      final id = m.scheduleLessonId;
      if (id == null) continue;
      final workType = m.workType ??
          _resolveWorkType(
            m,
            subjectName: lessonSubject[id],
            subjectByName: subjectByName,
          );
      map.putIfAbsent(id, () => <LessonGrade>[]).add(LessonGrade(
        m.value,
        m.createdAt,
        workType: workType,
        isAbsence: m.isAbsence,
      ));
    }

    for (final list in map.values) {
      list.sort((a, b) {
        final ad = a.receivedAt, bd = b.receivedAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    }
    return LessonGradesLookup._(map);
  }

  static String? _resolveWorkType(
      Mark mark, {
        String? subjectName,
        required Map<String, SubjectGrade> subjectByName,
      }) {
    if (subjectName == null) return null;
    final subject = subjectByName[subjectName];
    if (subject == null) return null;

    final candidates = <_WorkTypeCandidate>[];
    for (final period in subject.periods) {
      for (final wt in period.workTypes) {
        for (var i = 0; i < wt.grades.length; i++) {
          if (wt.grades[i] != mark.value) continue;
          candidates.add(_WorkTypeCandidate(
            workType: wt.workType,
            date: wt.dateAt(i),
          ));
        }
      }
    }
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.workType;

    final target = mark.createdAt ?? mark.date;
    if (target == null) return candidates.first.workType;

    candidates.sort((a, b) {
      final da = a.date == null
          ? const Duration(days: 99999)
          : a.date!.difference(target).abs();
      final db = b.date == null
          ? const Duration(days: 99999)
          : b.date!.difference(target).abs();
      return da.compareTo(db);
    });
    return candidates.first.workType;
  }

  List<LessonGrade> forLesson(Lesson lesson) {
    final primary = lesson.id;
    final secondary = lesson.secondaryId;
    if (primary == null && secondary == null) return const [];
    final result = <LessonGrade>[];
    if (primary != null) {
      final list = _byLessonId[primary];
      if (list != null) result.addAll(list);
    }
    if (secondary != null) {
      final list = _byLessonId[secondary];
      if (list != null) result.addAll(list);
    }
    return result;
  }
}

class _WorkTypeCandidate {
  final String workType;
  final DateTime? date;
  const _WorkTypeCandidate({required this.workType, this.date});
}