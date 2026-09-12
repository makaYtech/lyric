import '../core/util/date_time.dart';

/// Одна оценка из /core/api/marks.
/// Ключевое, что здесь есть и чего нет в progress/json:
/// - schedule_lesson_id — прямая ссылка на урок из schedule_items;
/// - created_at — когда выставлена ("dd.MM.yyyy HH:mm", НЕ ISO);
/// - date — дата урока, к которой привязана оценка;
/// - subject_id — числовой id предмета.
class Mark {
  final int id;
  final int value;
  final int? subjectId;
  final DateTime? createdAt;
  final DateTime? date;
  final int? scheduleLessonId;
  final int? groupId;
  final int? teacherId;

  const Mark({
    required this.id,
    required this.value,
    this.subjectId,
    this.createdAt,
    this.date,
    this.scheduleLessonId,
    this.groupId,
    this.teacherId,
  });

  factory Mark.fromJson(Map<String, dynamic> json) => Mark(
    id: json['id'] as int? ?? 0,
    value: _extractValue(json),
    subjectId: json['subject_id'] as int?,
    createdAt: parseEposDateTime(json['created_at']),
    date: parseEposDate(json['date']),
    scheduleLessonId: json['schedule_lesson_id'] as int?,
    groupId: json['group_id'] as int?,
    teacherId: json['teacher_id'] as int?,
  );

  static int _extractValue(Map<String, dynamic> json) {
    final values = json['values'];
    if (values is List) {
      for (final v in values.whereType<Map<String, dynamic>>()) {
        final grade = v['grade'];
        if (grade is Map<String, dynamic>) {
          final five = grade['five'];
          if (five is num) return five.toInt();
        }
      }
    }
    final name = json['name'];
    if (name is String) {
      final v = int.tryParse(name);
      if (v != null) return v;
    }
    return 0;
  }
}