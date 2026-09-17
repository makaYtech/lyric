import '../core/util/date_time.dart';

/// Одно отсутствие ученика на уроке из /core/api/student_profiles
/// (поле attendances[]).
///
/// absence_reason_id:
///   2 — пропуск по уважительной причине (жёлтая «Н»);
///   иное / null — без уважительной (красная «Н»).
///
/// Точные значения остальных id пока не знаем, поэтому трактуем строго:
/// только 2 — уважительная. Что найдём нового — расширим.
class Attendance {
  final int id;
  final int? scheduleLessonId;
  final int? subjectId;
  final int? teacherId;
  final DateTime? date;
  final int? absenceReasonId;

  const Attendance({
    required this.id,
    this.scheduleLessonId,
    this.subjectId,
    this.teacherId,
    this.date,
    this.absenceReasonId,
  });

  bool get isExcused => absenceReasonId == 2;

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
    id: json['id'] as int? ?? 0,
    scheduleLessonId: json['schedule_lesson_id'] as int?,
    subjectId: json['subject_id'] as int?,
    teacherId: json['teacher_id'] as int?,
    date: parseEposDate(json['date']),
    absenceReasonId: json['absence_reason_id'] as int?,
  );

  Map<String, dynamic> toRow(int yearId) => {
    'id': id,
    'year_id': yearId,
    'date': date == null ? null : isoDate(date!),
    'schedule_lesson_id': scheduleLessonId,
    'subject_id': subjectId,
    'teacher_id': teacherId,
    'absence_reason_id': absenceReasonId,
  };

  factory Attendance.fromRow(Map<String, dynamic> r) => Attendance(
    id: r['id'] as int,
    scheduleLessonId: r['schedule_lesson_id'] as int?,
    subjectId: r['subject_id'] as int?,
    teacherId: r['teacher_id'] as int?,
    date: r['date'] == null ? null : DateTime.tryParse(r['date'] as String),
    absenceReasonId: r['absence_reason_id'] as int?,
  );
}
