import '../core/util/date_time.dart';

/// Одна запись ДЗ внеурочного занятия из /ec/api/ec_student_homeworks.
///
/// Матчится к уроку по homework.id → EcScheduleItem.homeworksToGive.
/// Структура 1:1 с обычным StudentHomework, но ветка с названием
/// предмета — через ec_activity.name, а не subject.name.
class EcHomework {
  final int id;
  final int homeworkId;
  final int entryId;
  final String description;
  final DateTime? assignedAt;
  final DateTime? dueDate;
  final int? ecActivityId;
  final String? activityName;
  final int? ecGroupId;

  const EcHomework({
    required this.id,
    required this.homeworkId,
    required this.entryId,
    required this.description,
    this.assignedAt,
    this.dueDate,
    this.ecActivityId,
    this.activityName,
    this.ecGroupId,
  });

  factory EcHomework.fromJson(Map<String, dynamic> j) {
    final entry = j['homework_entry'] as Map<String, dynamic>? ?? const {};
    final hw = entry['homework'] as Map<String, dynamic>? ?? const {};
    final activity = hw['ec_activity'] as Map<String, dynamic>? ?? const {};

    return EcHomework(
      id: j['id'] as int? ?? 0,
      homeworkId: hw['id'] as int? ?? 0,
      entryId: entry['id'] as int? ?? 0,
      description: entry['description'] as String? ?? '',
      assignedAt: parseEposDate(hw['date_assigned_on']),
      dueDate: parseEposDate(hw['date_prepared_for']),
      ecActivityId: hw['ec_activity_id'] as int?,
      activityName: activity['name'] as String?,
      ecGroupId: hw['ec_group_id'] as int?,
    );
  }
}
