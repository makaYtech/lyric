import '../../core/util/json.dart';

/// ФИО, класс и профиль обучения из полного ответа
/// /core/api/student_profiles/{id}.
class StudentProfile {
  final List<String> schoolNames;
  final String userName;
  final String className;
  final String curriculumName;

  /// id класса (class_unit.id) — нужен для /ec/api/ec_schedule_items:
  /// без class_unit_ids сервер может отдать пустой список внеурочки.
  final int? classUnitId;

  StudentProfile({
    required this.schoolNames,
    required this.userName,
    required this.className,
    required this.curriculumName,
    this.classUnitId,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final classUnit = json['class_unit'] as Map<String, dynamic>?;
    final curricula = json['curricula'] as Map<String, dynamic>?;

    return StudentProfile(
      schoolNames: _extractSchoolNames(json),
      userName: json.strOr('user_name', '—'),
      className: classUnit?.strOr('name', '—') ?? '—',
      curriculumName: curricula?.strOr('name', '—') ?? '—',
      classUnitId:
          classUnit?.intOrNull('id') ?? json.intOrNull('class_unit_id'),
    );
  }

  /// Школы приходят либо напрямую как school_names (наш кэш), либо
  /// внутри profiles[].school_shortname (ответ /acl/api/users).
  static List<String> _extractSchoolNames(Map<String, dynamic> json) {
    final direct = json['school_names'];
    if (direct is List) {
      return direct.whereType<String>().toList();
    }
    final profiles = json['profiles'];
    if (profiles is! List) return const [];
    return profiles
        .whereType<Map<String, dynamic>>()
        .map((p) => p['school_shortname'])
        .whereType<String>()
        .toSet()
        .toList();
  }

  /// Упрощённая форма для кэша — только то, что реально показываем.
  Map<String, dynamic> toJson() => {
    'school_names': schoolNames,
    'user_name': userName,
    'class_unit': {'name': className, 'id': classUnitId},
    'class_unit_id': classUnitId,
    'curricula': {'name': curriculumName},
  };
}
