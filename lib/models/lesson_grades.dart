import 'lesson.dart';
import 'mark.dart';

/// Одна оценка на уроке — значение + когда её получили.
class LessonGrade {
  final int value;
  final DateTime? receivedAt;
  const LessonGrade(this.value, this.receivedAt);
}

/// Быстрый поиск оценок по id урока из schedule_items
/// (Mark.scheduleLessonId == Lesson.id).
/// У пары уроков (mergeLessonPairs) secondaryId — id второго урока,
/// поэтому его оценки тоже подтягиваются.
class LessonGradesLookup {
  final Map<int, List<LessonGrade>> _byLessonId;

  const LessonGradesLookup._(this._byLessonId);

  static const empty = LessonGradesLookup._({});

  factory LessonGradesLookup.fromMarks(List<Mark>? marks) {
    if (marks == null || marks.isEmpty) return empty;
    final map = <int, List<LessonGrade>>{};
    for (final m in marks) {
      final id = m.scheduleLessonId;
      if (id == null) continue;
      map.putIfAbsent(id, () => <LessonGrade>[])
          .add(LessonGrade(m.value, m.createdAt));
    }
    // Внутри урока — по возрастанию времени получения.
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