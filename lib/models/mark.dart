import '../core/util/date_time.dart';

class Mark {
  final int id;
  final int value;
  final int? subjectId;
  final DateTime? createdAt;
  final DateTime? date;
  final int? scheduleLessonId;
  final int? groupId;
  final int? teacherId;

  /// Тип работы (контрольная, домашняя, ...) — если API его отдаёт.
  final String? workType;

  /// «Отсутствовал» — сервер ставит name = "шкала оценивания X" вместо
  /// цифры. Это не оценка в обычном смысле, но приходит тем же эндпоинтом.
  /// value в этом случае = 0, и в UI это рисуется как бейдж «Н».
  final bool isAbsence;

  const Mark({
    required this.id,
    required this.value,
    this.subjectId,
    this.createdAt,
    this.date,
    this.scheduleLessonId,
    this.groupId,
    this.teacherId,
    this.workType,
    this.isAbsence = false,
  });

  factory Mark.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final nameStr = rawName is String ? rawName.trim() : '';
    final absence =
        nameStr.isNotEmpty && int.tryParse(nameStr) == null;

    return Mark(
      id: json['id'] as int? ?? 0,
      value: _extractValue(json),
      subjectId: json['subject_id'] as int?,
      createdAt: parseEposDateTime(json['created_at']),
      date: parseEposDate(json['date']),
      scheduleLessonId: json['schedule_lesson_id'] as int?,
      groupId: json['group_id'] as int?,
      teacherId: json['teacher_id'] as int?,
      workType: _extractWorkType(json),
      isAbsence: absence,
    );
  }

  static String? _extractWorkType(Map<String, dynamic> json) {
    final candidates = <Object?>[
      json['control_form_name'],
      json['work_type'],
      json['work_type_name'],
      json['control_form'],
      json['form_name'],
    ];
    final values = json['values'];
    if (values is List) {
      for (final v in values.whereType<Map<String, dynamic>>()) {
        candidates.addAll([
          v['control_form_name'],
          v['work_type'],
          v['control_form'],
        ]);
      }
    }
    for (final c in candidates) {
      if (c is String) {
        final t = c.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

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