/// Одна группа ученика из ответа /core/api/student_profiles/{id}.
/// Из него нам нужен только id (для schedule_items), но имя тоже
/// сохраняем — мало ли, пригодится для UI.
class StudentGroup {
  final int id;
  final String name;

  const StudentGroup({required this.id, required this.name});

  factory StudentGroup.fromJson(Map<String, dynamic> json) => StudentGroup(
    id: json['id'] as int,
    name: json['name'] as String? ?? '—',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}