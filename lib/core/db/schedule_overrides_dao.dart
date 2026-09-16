import 'package:sqflite/sqflite.dart';

import '../../models/schedule_override.dart';
import '../util/date_time.dart';
import 'app_database.dart';

/// CRUD над таблицей schedule_overrides.
///
/// Отдельная таблица, а не поле в lessons: серверный refresh перезаписывает
/// lessons целиком, а правки пользователя должны это пережить. См. модель
/// ScheduleOverride — там подробнее про смысл.
class ScheduleOverridesDao {
  Future<List<ScheduleOverride>> loadWeek(
      int yearId,
      DateTime monday,
      ) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    final rows = await db.query(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
      orderBy: 'date ASC, id ASC',
    );
    return rows.map(ScheduleOverride.fromRow).toList();
  }

  Future<List<ScheduleOverride>> loadDay(
      int yearId,
      DateTime date,
      ) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date = ?',
      whereArgs: [yearId, isoDate(date)],
      orderBy: 'id ASC',
    );
    return rows.map(ScheduleOverride.fromRow).toList();
  }

  /// Вставка. Возвращает id.
  Future<int> insert(ScheduleOverride o) async {
    final db = await AppDatabase.instance.database;
    return db.insert(AppDatabase.tableScheduleOverrides, o.toRow());
  }

  /// Вставка нескольких одной транзакцией. Возвращает id'ы вставленных
  /// записей — нужны для undo-снакбара («отменить только что сделанное»).
  Future<List<int>> insertAll(List<ScheduleOverride> overrides) async {
    if (overrides.isEmpty) return const [];
    final db = await AppDatabase.instance.database;
    final ids = <int>[];
    await db.transaction((txn) async {
      for (final o in overrides) {
        final id = await txn.insert(
          AppDatabase.tableScheduleOverrides,
          o.toRow(),
        );
        ids.add(id);
      }
    });
    return ids;
  }

  /// Удаление одного override по id. Для «откатить конкретную правку».
  Future<void> deleteById(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удаление пачки по id. Используется undo-снакбаром.
  Future<void> deleteByIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'id IN (${List.filled(list.length, '?').join(',')})',
      whereArgs: list,
    );
  }

  /// Удаление всех правок, задевающих конкретный урок — и как primary,
  /// и как secondary.
  Future<void> deleteForLesson(
      int yearId,
      DateTime date,
      int lessonId,
      ) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date = ? '
          'AND (primary_lesson_id = ? OR secondary_lesson_id = ?)',
      whereArgs: [yearId, isoDate(date), lessonId, lessonId],
    );
  }

  /// Снести все правки за день.
  Future<void> deleteDay(int yearId, DateTime date) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date = ?',
      whereArgs: [yearId, isoDate(date)],
    );
  }

  /// Снести все правки за неделю.
  Future<void> deleteWeek(int yearId, DateTime monday) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
    );
  }

  /// Полный сброс правок.
  Future<void> clearAll() async {
    final db = await AppDatabase.instance.database;
    await db.delete(AppDatabase.tableScheduleOverrides);
  }

  Future<int> count() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${AppDatabase.tableScheduleOverrides}',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  /// Удалить все reorder-записи дня. Вызывается перед вставкой новой —
  /// один reorder на день, предыдущий заменяется.
  Future<void> deleteReordersForDay(int yearId, DateTime date) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      AppDatabase.tableScheduleOverrides,
      where: 'year_id = ? AND date = ? AND kind = ?',
      whereArgs: [yearId, isoDate(date), ScheduleOverrideKind.reorder.name],
    );
  }
}