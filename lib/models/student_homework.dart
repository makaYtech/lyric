import '../core/util/date_time.dart';
import 'homework_attachment.dart';

/// Один элемент из /core/api/student_homeworks.
/// Расписанию нужно сопоставление homework_id → текст ДЗ и вложения,
/// а также id самой записи student_homework — без него нельзя
/// прикрепить свой файл (PUT идёт именно по нему).
///
/// Поля даты и предмета нужны для режима «группировка по дедлайну»:
/// когда он включён, расписание показывает не то, что задали в этот
/// день, а то, что надо сдать к этому дню (см. HomeworkPrefs.groupByDue).
class StudentHomework {
  /// id записи student_homework — то, что уходит в PUT-урл.
  final int id;
  final int homeworkId;
  final String description;

  /// Когда задали (date_assigned_on).
  final DateTime? assignedAt;

  /// Сделать до (date_prepared_for).
  final DateTime? dueDate;

  /// id предмета. Нужен для матчинга по предмету при группировке
  /// по дедлайну: на уроке «Русский» показываем только русские ДЗ.
  final int? subjectId;

  final List<HomeworkAttachment> attachments;

  const StudentHomework({
    required this.id,
    required this.homeworkId,
    required this.description,
    this.assignedAt,
    this.dueDate,
    this.subjectId,
    this.attachments = const [],
  });

  factory StudentHomework.fromJson(Map<String, dynamic> json) {
    final entry = json['homework_entry'] as Map<String, dynamic>?;
    final hw = entry?['homework'] as Map<String, dynamic>?;
    final subject = hw?['subject'] as Map<String, dynamic>?;

    final rawAtt = entry?['attachments'];
    final attachments = rawAtt is List
        ? rawAtt
              .whereType<Map<String, dynamic>>()
              .map(HomeworkAttachment.fromJson)
              .where((a) => a.url.isNotEmpty)
              .toList()
        : const <HomeworkAttachment>[];

    return StudentHomework(
      id: json['id'] as int? ?? 0,
      homeworkId: hw?['id'] as int? ?? 0,
      description: entry?['description'] as String? ?? '',
      assignedAt: parseEposDate(hw?['date_assigned_on']),
      dueDate: parseEposDate(hw?['date_prepared_for']),
      subjectId: subject?['id'] as int? ?? hw?['subject_id'] as int?,
      attachments: attachments,
    );
  }
}
