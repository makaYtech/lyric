import '../../core/util/json.dart';

/// Минимальный срез /core/api/teacher_profiles — нам нужно только имя.
class TeacherProfile {
  final int id;
  final String name;

  const TeacherProfile({required this.id, required this.name});

  factory TeacherProfile.fromJson(Map<String, dynamic> json) =>
      TeacherProfile(id: json.intOr('id', 0), name: json.strOr('name', '—'));
}
