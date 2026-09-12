import '../core/util/date_time.dart';

/// Одна запись ДЗ из /core/api/student_homeworks.
///
/// Структура (реальный ответ, сентябрь 2026):
///   { id, created_at,
///     homework_entry: {
///       id, description,
///       homework: {
///         id, teacher_id, subject_id, group_id,
///         date_assigned_on,     // «когда задал» (дата урока)
///         date_prepared_for,    // «сделать до»
///         subject: { id, name },
///         is_required, mark_required,
///       }
///     }
///   }
///
/// teacherName пока всегда null: в ответе есть только teacher_id,
/// ФИО резолвится отдельным запросом к /core/api/teacher_profiles.
/// Добавим позже — модель и UI уже готовы.
class Homework {
  /// id записи student_homeworks — уникален среди всех ДЗ ученика.
  final int id;

  /// id самого ДЗ (homework_entry.homework.id) — общий для всех учеников.
  final int homeworkId;

  /// id записи homework_entry — по нему, если что, ищутся вложения.
  final int entryId;

  final String description;

  /// «Сделать до» — к какому дню готово.
  final DateTime? dueDate;

  /// «Когда задал» — дата выдачи.
  final DateTime? assignedAt;

  /// Когда запись создана в ЭПОСе (обычно совпадает с assignedAt).
  final DateTime? createdAt;

  final String? subjectName;
  final int? subjectId;
  final int? teacherId;

  /// ФИО учителя. Пока всегда null — резолвится позже через
  /// /core/api/teacher_profiles. UI просто не рисует блок, если null.
  final String? teacherName;

  final int? groupId;
  final bool isRequired;
  final bool markRequired;

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
  });

  /// Дата, к которой группируем на экране ДЗ.
  ///
  /// Берём день, когда задали (`date_assigned_on`), а НЕ «сделать до».
  /// Иначе ДЗ, заданное в понедельник и «сделать до субботы», покажется
  /// в субботу — что сбивает с толку: ученику важно видеть его в тот
  /// день, когда урок реально был.
  ///
  /// Fallback на dueDate — на случай, если assignedAt почему-то null.
  DateTime? get date => assignedAt ?? dueDate;

  factory Homework.fromJson(Map<String, dynamic> json) {
    final entry = json['homework_entry'] as Map<String, dynamic>? ?? const {};
    final hw = entry['homework'] as Map<String, dynamic>? ?? const {};
    final subject = hw['subject'] as Map<String, dynamic>? ?? const {};

    return Homework(
      id: json['id'] as int? ?? 0,
      homeworkId: hw['id'] as int? ?? 0,
      entryId: entry['id'] as int? ?? 0,
      description: entry['description'] as String? ?? '',
      dueDate: parseEposDate(hw['date_prepared_for']),
      assignedAt: parseEposDate(hw['date_assigned_on']),
      createdAt: parseEposDateTime(json['created_at']),
      subjectName: _findSubjectName(json, hw, entry, subject),
      subjectId: subject['id'] as int? ?? hw['subject_id'] as int?,
      teacherId: hw['teacher_id'] as int?,
      // teacherName резолвится отдельно — пока null.
      groupId: hw['group_id'] as int?,
      isRequired: hw['is_required'] as bool? ?? false,
      markRequired: hw['mark_required'] as bool? ?? false,
    );
  }

  /// Название предмета. Основной путь — `homework.subject.name`,
  /// но на всякий случай проверяем ещё плоские `subject_name`
  /// на всех трёх уровнях вложенности. Пустые строки игнорим.
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
  };

  factory Homework.fromCache(Map<String, dynamic> json) => Homework(
    id: json['id'] as int? ?? 0,
    homeworkId: json['homework_id'] as int? ?? 0,
    entryId: json['entry_id'] as int? ?? 0,
    description: json['description'] as String? ?? '',
    dueDate: _parse(json['due_date']),
    assignedAt: _parse(json['assigned_at']),
    createdAt: _parse(json['created_at']),
    subjectName: json['subject_name'] as String?,
    subjectId: json['subject_id'] as int?,
    teacherId: json['teacher_id'] as int?,
    teacherName: json['teacher_name'] as String?,
    groupId: json['group_id'] as int?,
    isRequired: json['is_required'] as bool? ?? false,
    markRequired: json['mark_required'] as bool? ?? false,
  );

  static DateTime? _parse(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}