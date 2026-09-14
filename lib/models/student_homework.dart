import 'homework_attachment.dart';

/// Один элемент из /core/api/student_homeworks.
/// Расписанию нужно сопоставление homework_id → текст ДЗ и вложения.
class StudentHomework {
  final int homeworkId;
  final String description;
  final List<HomeworkAttachment> attachments;

  const StudentHomework({
    required this.homeworkId,
    required this.description,
    this.attachments = const [],
  });

  factory StudentHomework.fromJson(Map<String, dynamic> json) {
    final entry = json['homework_entry'] as Map<String, dynamic>?;
    final hw = entry?['homework'] as Map<String, dynamic>?;

    final rawAtt = entry?['attachments'];
    final attachments = rawAtt is List
        ? rawAtt
        .whereType<Map<String, dynamic>>()
        .map(HomeworkAttachment.fromJson)
        .where((a) => a.url.isNotEmpty)
        .toList()
        : const <HomeworkAttachment>[];

    return StudentHomework(
      homeworkId: hw?['id'] as int? ?? 0,
      description: entry?['description'] as String? ?? '',
      attachments: attachments,
    );
  }
}