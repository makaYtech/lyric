/// Один учебный год из /core/api/academic_years.
class AcademicYear {
  final int id;
  final String name;
  final bool currentYear;

  AcademicYear({
    required this.id,
    required this.name,
    required this.currentYear,
  });

  factory AcademicYear.fromJson(Map<String, dynamic> json) {
    return AcademicYear(
      id: json['id'] as int,
      name: json['name'] as String,
      currentYear: json['current_year'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'current_year': currentYear,
      };
}
