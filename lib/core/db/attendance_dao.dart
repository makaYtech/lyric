import 'package:sqflite/sqflite.dart';

import '../../models/attendance.dart';
import 'app_database.dart';

/// Отсутствия живут по учебному году: перезаписываем весь список
/// целиком при каждом refresh. Записей за год — сотни, не страшно.
class AttendanceDao {
  Future<void> saveAll(int yearId, List<Attendance> list) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableAttendances,
        where: 'year_id = ?',
        whereArgs: [yearId],
      );
      final batch = txn.batch();
      for (final a in list) {
        batch.insert(AppDatabase.tableAttendances, {
          ...a.toRow(yearId),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Attendance>> loadAll(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableAttendances,
      where: 'year_id = ?',
      whereArgs: [yearId],
    );
    return rows.map(Attendance.fromRow).toList();
  }

  Future<DateTime?> lastUpdated(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableAttendances,
      columns: ['updated_at'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }
}
