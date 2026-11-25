import 'package:sqflite/sqflite.dart';

import '../../domain/attendance/attendance.dart';
import './app_database.dart';
import './dao_utils.dart';

/// Отсутствия живут по учебному году: при refresh перезаписываем весь
/// список целиком — записей сотни, не страшно.
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
    return lastUpdatedAt(
      db,
      AppDatabase.tableAttendances,
      where: 'year_id = ?',
      whereArgs: [yearId],
    );
  }
}
