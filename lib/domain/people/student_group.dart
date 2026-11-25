import '../../core/util/json.dart';

/// Одна группа ученика из ответа /core/api/student_profiles/{id}.
class StudentGroup {
  final int id;
  final String name;

  const StudentGroup({required this.id, required this.name});

  factory StudentGroup.fromJson(Map<String, dynamic> json) =>
      StudentGroup(id: json['id'] as int, name: json.strOr('name', '—'));

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
