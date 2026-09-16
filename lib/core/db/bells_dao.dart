import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Кэш расписания звонков. Храним СЫРОЙ JSON — модель и парсер уже есть
/// в models/bells_timetable.dart, отдельная сериализация по полям тут
/// лишняя. Если сервер поменяет схему — ломается ровно один fromJson.
///
/// Один timetable на учебный год (в нашей школе — id 124412).
class BellsDao {
  Future<void> save(int yearId, int timetableId, String rawJson) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      AppDatabase.tableBells,
      {
        'id': timetableId,
        'year_id': yearId,
        'payload_json': rawJson,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> loadRaw(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableBells,
      columns: ['payload_json'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload_json'] as String?;
  }

  Future<DateTime?> lastUpdated(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableBells,
      columns: ['updated_at'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  Future<void> clearYear(int yearId) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableBells,
      where: 'year_id = ?',
      whereArgs: [yearId],
    );
  }
}