import 'attendance.dart';
import 'lesson.dart';

/// Поиск отсутствий по id урока из schedule_items
/// (Attendance.scheduleLessonId == Lesson.id).
///
/// Для пары (mergeLessonPairs) secondaryId — id второго урока, поэтому
/// отсутствие по нему тоже подтягивается. Если на оба урока пары есть
/// Н (в жизни так не бывает) — показываем ту, что на primary.
class LessonAttendanceLookup {
  final Map<int, Attendance> _byLessonId;

  const LessonAttendanceLookup._(this._byLessonId);

  static const empty = LessonAttendanceLookup._({});

  factory LessonAttendanceLookup.fromAttendances(
    List<Attendance>? attendances,
  ) {
    if (attendances == null || attendances.isEmpty) return empty;
    final map = <int, Attendance>{};
    for (final a in attendances) {
      final id = a.scheduleLessonId;
      if (id == null) continue;
      map.putIfAbsent(id, () => a);
    }
    return LessonAttendanceLookup._(map);
  }

  Attendance? forLesson(Lesson lesson) {
    final primary = lesson.id;
    if (primary != null) {
      final a = _byLessonId[primary];
      if (a != null) return a;
    }
    final secondary = lesson.secondaryId;
    if (secondary != null) return _byLessonId[secondary];
    return null;
  }
}
