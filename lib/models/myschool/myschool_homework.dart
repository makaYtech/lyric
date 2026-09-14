import '../../core/util/date_time.dart';

class MySchoolMaterial {
  final String name;
  final String link;
  final double size;

  const MySchoolMaterial({
    required this.name,
    required this.link,
    this.size = 0,
  });

  factory MySchoolMaterial.fromJson(Map<String, dynamic> j) =>
      MySchoolMaterial(
        name: j['name'] as String? ?? '—',
        link: j['link'] as String? ?? '',
        size: (j['size'] as num?)?.toDouble() ?? 0,
      );
}

/// Одна запись ДЗ из datamart → obj_type = student_homeworks_materials.
class MySchoolHomework {
  final String id;
  final String description;
  final List<MySchoolMaterial> materials;
  final DateTime? issueDate;
  final DateTime? planReadyDate;
  final DateTime? createDatetime;
  final DateTime? sendDatetime;
  final String? subjectName;
  final String? subjectId;
  final String? teacherId;
  final String? lessonId;

  const MySchoolHomework({
    required this.id,
    required this.description,
    this.materials = const [],
    this.issueDate,
    this.planReadyDate,
    this.createDatetime,
    this.sendDatetime,
    this.subjectName,
    this.subjectId,
    this.teacherId,
    this.lessonId,
  });

  bool get isEmpty => description.trim().toLowerCase() == 'не задано';

  factory MySchoolHomework.fromJson(Map<String, dynamic> j) {
    final rawMaterials = j['materials'] as List<dynamic>? ?? const [];
    return MySchoolHomework(
      id: j['id'] as String? ?? '',
      description: j['description'] as String? ?? '',
      materials: rawMaterials
          .whereType<Map<String, dynamic>>()
          .map(MySchoolMaterial.fromJson)
          .toList(),
      issueDate: parseEposDate(j['issue_date']),
      planReadyDate: parseEposDate(j['plan_ready_date']),
      createDatetime: parseEposDateTime(j['create_datetime']),
      sendDatetime: parseEposDateTime(j['send_datetime']),
      subjectName: _nonEmpty(j['subject_name']),
      subjectId: j['subject_id'] as String?,
      teacherId: j['teacher_id'] as String?,
      lessonId: j['issue_lesson_id'] as String?,
    );
  }

  static String? _nonEmpty(Object? raw) {
    if (raw is! String) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  DateTime? get date => issueDate ?? planReadyDate;
}