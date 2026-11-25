import '../../core/util/date_time.dart';
import '../../core/util/json.dart';
import './homework_attachment.dart';

/// Одна запись ДЗ из /core/api/student_homeworks.
///
/// Структура: { id, created_at, homework_entry: { id, description,
/// attachments[], homework: { id, teacher_id, subject_id, group_id,
/// date_assigned_on, date_prepared_for, subject, is_required,
/// mark_required } } }.
class Homework {
  /// id записи student_homeworks — уникален среди всех ДЗ ученика.
  final int id;

  /// id самого ДЗ (homework_entry.homework.id) — общий для всех учеников.
  final int homeworkId;

  /// id записи homework_entry — по нему ищутся вложения.
  final int entryId;

  final String description;

  /// «Сделать до».
  final DateTime? dueDate;

  /// «Когда задал» — дата выдачи.
  final DateTime? assignedAt;

  /// Когда запись создана в ЭПОСе (обычно совпадает с assignedAt).
  final DateTime? createdAt;

  final String? subjectName;
  final int? subjectId;
  final int? teacherId;

  /// ФИО учителя: в ответе есть только teacher_id, имя резолвится
  /// отдельно через /core/api/teacher_profiles.
  final String? teacherName;

  final int? groupId;
  final bool isRequired;
  final bool markRequired;

  /// Файлы учителя из homework_entry.attachments[].
  final List<HomeworkAttachment> attachments;

  /// Файлы, прикреплённые самим учеником (корневой attachments[]).
  final List<HomeworkAttachment> myAttachments;

  const Homework({
    required this.id,
    required this.homeworkId,
    required this.entryId,
    required this.description,
    this.dueDate,
    this.assignedAt,
    this.createdAt,
    this.subjectName,
    this.subjectId,
    this.teacherId,
    this.teacherName,
    this.groupId,
    this.isRequired = false,
    this.markRequired = false,
    this.attachments = const [],
    this.myAttachments = const [],
  });

  /// Группируем по дню, когда задали, а не по «сделать до»: иначе ДЗ
  /// показывается не в тот день, когда был урок. Fallback — dueDate.
  DateTime? get date => assignedAt ?? dueDate;

  factory Homework.fromJson(Map<String, dynamic> json) {
    final entry = json['homework_entry'] as Map<String, dynamic>? ?? const {};
    final hw = entry['homework'] as Map<String, dynamic>? ?? const {};
    final subject = hw['subject'] as Map<String, dynamic>? ?? const {};

    return Homework(
      id: json.intOr('id', 0),
      homeworkId: hw.intOr('id', 0),
      entryId: entry.intOr('id', 0),
      description: entry.str('description'),
      dueDate: parseEposDate(hw['date_prepared_for']),
      assignedAt: parseEposDate(hw['date_assigned_on']),
      createdAt: parseEposDateTime(json['created_at']),
      subjectName: _findSubjectName(json, hw, entry, subject),
      subjectId: subject.intOrNull('id') ?? hw.intOrNull('subject_id'),
      teacherId: hw.intOrNull('teacher_id'),
      groupId: hw.intOrNull('group_id'),
      isRequired: hw.boolOr('is_required'),
      markRequired: hw.boolOr('mark_required'),
      attachments: HomeworkAttachment.listFromJson(entry['attachments']),
      myAttachments: HomeworkAttachment.listFromJson(json['attachments']),
    );
  }

  /// Основной путь — homework.subject.name; на всякий случай проверяем
  /// плоские subject_name на всех уровнях вложенности.
  static String? _findSubjectName(
    Map<String, dynamic> json,
    Map<String, dynamic> hw,
    Map<String, dynamic> entry,
    Map<String, dynamic> subject,
  ) {
    final candidates = <Object?>[
      subject['name'],
      hw['subject_name'],
      entry['subject_name'],
      json['subject_name'],
    ];
    for (final c in candidates) {
      if (c is String) {
        final t = c.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'homework_id': homeworkId,
    'entry_id': entryId,
    'description': description,
    'due_date': dueDate?.toIso8601String(),
    'assigned_at': assignedAt?.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
    'subject_name': subjectName,
    'subject_id': subjectId,
    'teacher_id': teacherId,
    'teacher_name': teacherName,
    'group_id': groupId,
    'is_required': isRequired,
    'mark_required': markRequired,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'my_attachments': myAttachments.map((a) => a.toJson()).toList(),
  };

  factory Homework.fromCache(Map<String, dynamic> json) => Homework(
    id: json.intOr('id', 0),
    homeworkId: json.intOr('homework_id', 0),
    entryId: json.intOr('entry_id', 0),
    description: json.str('description'),
    dueDate: _parse(json['due_date']),
    assignedAt: _parse(json['assigned_at']),
    createdAt: _parse(json['created_at']),
    subjectName: json['subject_name'] as String?,
    subjectId: json.intOrNull('subject_id'),
    teacherId: json.intOrNull('teacher_id'),
    teacherName: json['teacher_name'] as String?,
    groupId: json.intOrNull('group_id'),
    isRequired: json.boolOr('is_required'),
    markRequired: json.boolOr('mark_required'),
    attachments: HomeworkAttachment.listFromJson(json['attachments']),
    myAttachments: HomeworkAttachment.listFromJson(json['my_attachments']),
  );

  static DateTime? _parse(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}
