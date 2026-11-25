import '../../core/util/date_time.dart';
import '../../core/util/json.dart';

/// Одно отсутствие ученика на уроке из /core/api/student_profiles
/// (поле attendances[]).
///
/// absence_reason_id == 2 — уважительная причина (жёлтая «Н»);
/// иное / null — без уважительной (красная «Н»).
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
    id: json.intOr('id', 0),
    scheduleLessonId: json.intOrNull('schedule_lesson_id'),
    subjectId: json.intOrNull('subject_id'),
    teacherId: json.intOrNull('teacher_id'),
    date: parseEposDate(json['date']),
    absenceReasonId: json.intOrNull('absence_reason_id'),
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
    scheduleLessonId: r.intOrNull('schedule_lesson_id'),
    subjectId: r.intOrNull('subject_id'),
    teacherId: r.intOrNull('teacher_id'),
    date: r['date'] == null ? null : DateTime.tryParse(r['date'] as String),
    absenceReasonId: r.intOrNull('absence_reason_id'),
  );
}
