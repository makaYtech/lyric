import '../../core/util/json.dart';
import '../../core/util/names.dart';

class ManagedClass {
  final String displayName;
  final int classLevelId;

  const ManagedClass({required this.displayName, required this.classLevelId});

  factory ManagedClass.fromJson(Map<String, dynamic> json) => ManagedClass(
    displayName: json.strOr('display_name', '—'),
    classLevelId: json.intOr('class_level_id', 0),
  );

  Map<String, dynamic> toJson() => {
    'display_name': displayName,
    'class_level_id': classLevelId,
  };
}

/// Кабинет учителя. Формат отображения: «Кабинет математики: 35»,
/// «Библиотека: 8», «Кабинет: 35» без имени, «Кабинет математики» без номера.
class TeacherRoom {
  final int id;
  final String name;
  final String number;

  const TeacherRoom({
    required this.id,
    required this.name,
    required this.number,
  });

  String get display {
    final n = name.trim();
    final num = number.trim();

    if (n.isEmpty) {
      return num.isEmpty ? '—' : 'Кабинет: $num';
    }

    final capName = capitalizeFirst(n);

    if (num.isEmpty) return capName;
    if (n.toLowerCase() == 'учебный кабинет') {
      return 'Кабинет: $num';
    }
    return '$capName: $num';
  }

  factory TeacherRoom.fromJson(Map<String, dynamic> json) => TeacherRoom(
    id: json.intOr('id', 0),
    name: json.str('name'),
    number: json['number']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'number': number};
}

/// Учитель для карточки в профиле. Данные — из /core/api/teacher_profiles.
class Teacher {
  final int id;
  final String fullName;
  final List<String> subjects;
  final List<TeacherRoom> rooms;

  /// id кабинетов, где учитель — ответственный (responsible_id).
  /// Заполняется отдельным запросом /core/api/rooms (см. TeachersService).
  final Set<int> ownedRoomIds;

  final List<ManagedClass> managedClasses;
  final List<String> roles;
  final int workload;
  final DateTime? hiredAt;
  final bool isNewcomer;
  final String? buildingName;
  final String? buildingAddress;

  const Teacher({
    required this.id,
    required this.fullName,
    this.subjects = const [],
    this.rooms = const [],
    this.ownedRoomIds = const {},
    this.managedClasses = const [],
    this.roles = const [],
    this.workload = 0,
    this.hiredAt,
    this.isNewcomer = false,
    this.buildingName,
    this.buildingAddress,
  });

  String? get primarySubject => subjects.isEmpty ? null : subjects.first;

  /// Кабинеты, где учитель — ответственный. Если таких нет — все.
  List<TeacherRoom> get ownRooms {
    final owned = rooms.where((r) => ownedRoomIds.contains(r.id)).toList();
    return owned.isNotEmpty ? owned : rooms;
  }

  List<String> get displayRoles {
    const map = {
      'deputy': 'Завуч',
      'ae_admin': 'Администратор',
      'ae_educator': 'Педагог ДО',
    };
    return roles.where((r) => r != 'teacher').map((r) => map[r] ?? r).toList();
  }

  /// >= 5 лет — «Давно преподаёт», 1..4 года — «Стаж: N лет»,
  /// меньше года или isNewcomer — «Новенький».
  String? get experienceLabel {
    if (isNewcomer) return 'Новенький';
    if (hiredAt == null) return null;
    final years = DateTime.now().difference(hiredAt!).inDays ~/ 365;
    if (years >= 5) return 'Давно преподаёт';
    if (years >= 1) return 'Стаж: $years ${_pluralYears(years)}';
    return 'Новенький';
  }

  static String _pluralYears(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'год';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'года';
    }
    return 'лет';
  }

  Teacher copyWith({Set<int>? ownedRoomIds}) => Teacher(
    id: id,
    fullName: fullName,
    subjects: subjects,
    rooms: rooms,
    ownedRoomIds: ownedRoomIds ?? this.ownedRoomIds,
    managedClasses: managedClasses,
    roles: roles,
    workload: workload,
    hiredAt: hiredAt,
    isNewcomer: isNewcomer,
    buildingName: buildingName,
    buildingAddress: buildingAddress,
  );

  factory Teacher.fromJson(Map<String, dynamic> json) {
    final rawSubjects = json.list('subjects');
    final rawRooms = json.list('rooms');
    final rawManaged = json.list('managed_class_units');
    final rawRoles = json.list('roles');
    final rawBuildings = json.list('buildings');

    Map<String, dynamic>? building;
    for (final b in rawBuildings.whereType<Map<String, dynamic>>()) {
      building = b;
      break;
    }

    final createdAt = json['created_at'];
    DateTime? hiredAt;
    if (createdAt is int && createdAt > 0) {
      hiredAt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    }

    final rawName =
        json['name'] as String? ??
        (json['user'] as Map<String, dynamic>?)?['full_name'] as String? ??
        '—';

    final subjectSet = <String>{};
    final subjects = <String>[];
    for (final s in rawSubjects.whereType<Map<String, dynamic>>()) {
      final name = (s['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      if (subjectSet.add(name)) subjects.add(name);
    }

    final roomSet = <String>{};
    final rooms = <TeacherRoom>[];
    for (final r in rawRooms.whereType<Map<String, dynamic>>()) {
      final room = TeacherRoom.fromJson(r);
      final key = '${room.name.toLowerCase()}|${room.number}';
      if (roomSet.add(key)) rooms.add(room);
    }

    return Teacher(
      id: json.intOr('id', 0),
      fullName: normalizeFullName(rawName),
      subjects: subjects,
      rooms: rooms,
      managedClasses: rawManaged
          .whereType<Map<String, dynamic>>()
          .map(ManagedClass.fromJson)
          .toList(),
      roles: rawRoles.whereType<String>().toList(),
      workload: json.intOr('workload', 0),
      hiredAt: hiredAt,
      isNewcomer: json.boolOr('is_newcomer'),
      buildingName: building?['name'] as String?,
      buildingAddress: building?['address'] as String?,
    );
  }
}
