/// ФИО, класс и профиль обучения — вытянуты из полного ответа
/// /core/api/student_profiles/{id}. Ответ там гораздо больше (учителя и т.д.),
/// но пока берём только то, что показываем на экране.
class StudentProfile {
  final List<String> schoolNames;
  final String userName;
  final String className;
  final String curriculumName;

  StudentProfile({
    required this.schoolNames,
    required this.userName,
    required this.className,
    required this.curriculumName,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    print('KEYS: ${json.keys.toList()}');
    print('PROFILES: ${json['profiles']}');
    final classUnit = json['class_unit'] as Map<String, dynamic>?;
    final curricula = json['curricula'] as Map<String, dynamic>?;
    final profiles = json['profiles'] as List<dynamic>? ?? [];
    final direct = json['school_names'];
    final List<String> schoolNames;
    if (direct is List) {
      schoolNames = direct.whereType<String>().toList();
    } else {
      final profiles = json['profiles'] as List<dynamic>? ?? [];
      schoolNames = profiles
          .whereType<Map<String, dynamic>>()
          .map((p) => p['school_shortname'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
    }
    return StudentProfile(
      schoolNames: schoolNames,
      userName: json['user_name'] as String? ?? '—',
      className: classUnit?['name'] as String? ?? '—',
      curriculumName: curricula?['name'] as String? ?? '—',
    );
  }

  /// Упрощённая форма для кэша — не полный ответ API, а только то,
  /// что реально показываем (полный ответ хранить в кэше избыточно).
  Map<String, dynamic> toJson() => {
        'school_names': schoolNames,
        'user_name': userName,
        'class_unit': {'name': className},
        'curricula': {'name': curriculumName},
      };
}
