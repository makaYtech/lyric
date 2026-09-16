import 'package:sqflite/sqflite.dart';

import '../../models/mark.dart';
import '../util/date_time.dart';
import 'app_database.dart';

/// marks живут по неделям: перезаписываем всю неделю за раз.
class MarksDao {
  Future<void> saveWeek(int yearId, DateTime monday, List<Mark> marks) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    final now = DateTime.now().toIso8601String();
    final mondayStr = isoDate(monday);
    final sundayStr = isoDate(sunday);

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableMarks,
        where: 'year_id = ? AND date BETWEEN ? AND ?',
        whereArgs: [yearId, mondayStr, sundayStr],
      );

      final batch = txn.batch();
      for (final m in marks) {
        final d = m.date ?? m.createdAt;
        if (d == null) continue;
        batch.insert(
          AppDatabase.tableMarks,
          {
            'id': m.id,
            'year_id': yearId,
            'date': isoDate(d),
            'value': m.value,
            'subject_id': m.subjectId,
            'created_at': m.createdAt?.toIso8601String(),
            'schedule_lesson_id': m.scheduleLessonId,
            'group_id': m.groupId,
            'teacher_id': m.teacherId,
            'updated_at': now,
            'work_type': m.workType,
            'is_absence': m.isAbsence ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Mark>> loadWeek(int yearId, DateTime monday) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    final rows = await db.query(
      AppDatabase.tableMarks,
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
    );
    return rows.map(_fromRow).toList();
  }

  Future<DateTime?> lastUpdated(int yearId, DateTime monday) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    final rows = await db.query(
      AppDatabase.tableMarks,
      columns: ['updated_at'],
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  Mark _fromRow(Map<String, dynamic> r) {
    final createdRaw = r['created_at'] as String?;
    final dateRaw = r['date'] as String?;
    return Mark(
      id: r['id'] as int,
      value: r['value'] as int,
      subjectId: r['subject_id'] as int?,
      createdAt: createdRaw == null ? null : DateTime.tryParse(createdRaw),
      date: dateRaw == null ? null : DateTime.tryParse(dateRaw),
      scheduleLessonId: r['schedule_lesson_id'] as int?,
      groupId: r['group_id'] as int?,
      teacherId: r['teacher_id'] as int?,
      workType: r['work_type'] as String?,
      isAbsence: (r['is_absence'] as int? ?? 0) == 1,
    );
  }
}