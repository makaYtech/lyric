import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/teacher.dart';
import 'app_database.dart';

/// Учителя хранятся по годам целиком: перезаписываем весь список при
/// каждом refresh. Учителей мало (десятки), вложенные структуры
/// (предметы/кабинеты/классы/роли) держим JSON-строками — читаются
/// они всегда вместе с учителем, отдельных выборок по ним нет.
class TeacherDao {
  Future<void> saveAll(int yearId, List<Teacher> teachers) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableTeachers,
        where: 'year_id = ?',
        whereArgs: [yearId],
      );

      final batch = txn.batch();
      for (final t in teachers) {
        if (t.id == 0) continue;
        batch.insert(
          AppDatabase.tableTeachers,
          {
            'id': t.id,
            'year_id': yearId,
            'full_name': t.fullName,
            'workload': t.workload,
            'hired_at': t.hiredAt?.toIso8601String(),
            'is_newcomer': t.isNewcomer ? 1 : 0,
            'building_name': t.buildingName,
            'building_address': t.buildingAddress,
            'roles_json': jsonEncode(t.roles),
            'subjects_json': jsonEncode(t.subjects),
            'managed_classes_json': jsonEncode(
              t.managedClasses.map((c) => c.toJson()).toList(),
            ),
            'rooms_json': jsonEncode(
              t.rooms.map((r) => r.toJson()).toList(),
            ),
            'owned_room_ids_json': jsonEncode(t.ownedRoomIds.toList()),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Teacher>> loadAll(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableTeachers,
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'full_name ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<DateTime?> lastUpdated(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableTeachers,
      columns: ['updated_at'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  Teacher _fromRow(Map<String, dynamic> r) => Teacher(
    id: r['id'] as int,
    fullName: r['full_name'] as String? ?? '—',
    subjects: _stringList(r['subjects_json']),
    rooms: _mapList(r['rooms_json']).map(TeacherRoom.fromJson).toList(),
    ownedRoomIds: _intSet(r['owned_room_ids_json']),
    managedClasses:
    _mapList(r['managed_classes_json']).map(ManagedClass.fromJson).toList(),
    roles: _stringList(r['roles_json']),
    workload: r['workload'] as int? ?? 0,
    hiredAt: _date(r['hired_at']),
    isNewcomer: (r['is_newcomer'] as int? ?? 0) == 1,
    buildingName: r['building_name'] as String?,
    buildingAddress: r['building_address'] as String?,
  );

  static List<String> _stringList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _mapList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Set<int> _intSet(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as List)
          .whereType<num>()
          .map((e) => e.toInt())
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}