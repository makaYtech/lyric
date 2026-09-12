/// Один элемент из /core/api/student_homeworks.
/// Нам нужно только сопоставление homework_id → текст ДЗ.
class StudentHomework {
  final int homeworkId;
  final String description;

  const StudentHomework({
    required this.homeworkId,
    required this.description,
  });

  factory StudentHomework.fromJson(Map<String, dynamic> json) {
    final entry = json['homework_entry'] as Map<String, dynamic>?;
    final hw = entry?['homework'] as Map<String, dynamic>?;
    return StudentHomework(
      homeworkId: hw?['id'] as int? ?? 0,
      description: entry?['description'] as String? ?? '',
    );
  }
}