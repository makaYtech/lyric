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
    final classUnit = json['class_unit'] as Map<String, dynamic>?;
    final curricula = json['curricula'] as Map<String, dynamic>?;

    return StudentProfile(
      schoolNames: _extractSchoolNames(json),
      userName: json['user_name'] as String? ?? '—',
      className: classUnit?['name'] as String? ?? '—',
      curriculumName: curricula?['name'] as String? ?? '—',
    );
  }

  /// Список школ может прийти двумя путями:
  /// - напрямую как `school_names` (наш собственный формат — в т.ч. в кэше);
  /// - внутри `profiles[].school_shortname` (ответ /acl/api/users).
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

  /// Упрощённая форма для кэша — не полный ответ API, а только то,
  /// что реально показываем (полный ответ хранить в кэше избыточно).
  Map<String, dynamic> toJson() => {
    'school_names': schoolNames,
    'user_name': userName,
    'class_unit': {'name': className},
    'curricula': {'name': curriculumName},
  };
}