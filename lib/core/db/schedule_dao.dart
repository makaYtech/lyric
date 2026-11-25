import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/schedule/day_schedule.dart';
import '../../domain/homework/homework_attachment.dart';
import '../../domain/schedule/lesson.dart';
import '../util/date_time.dart';
import './app_database.dart';
import './dao_utils.dart';

/// Расписание и ДЗ: одна строка на урок, без истории — просто
/// перезаписываем по id урока.
class ScheduleDao {
  Future<void> saveWeek(int yearId, List<DaySchedule> days) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // Пустой список сохранять нечего.
    if (days.isEmpty) return;
    final monday = days.first.date;
    final sunday = monday.add(const Duration(days: 6));

    await db.transaction((txn) async {
      // Перезаписываем неделю целиком: урок, пропавший из ответа сервера,
      // должен пропасть и в БД, иначе оффлайн покажет фантом.
      await txn.delete(
        AppDatabase.tableLessons,
        where: 'year_id = ? AND date BETWEEN ? AND ?',
        whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
      );

      final batch = txn.batch();
      for (final day in days) {
        final dateStr = isoDate(day.date);
        for (final lesson in day.lessons) {
          if (lesson.id == null) continue; // мок/данные без id не сохраняем
          batch.insert(AppDatabase.tableLessons, {
            'id': lesson.id,
            'year_id': yearId,
            'date': dateStr,
            'start_time': lesson.startTime,
            'end_time': lesson.endTime,
            'subject': lesson.subject,
            'subject_id': lesson.subjectId,
            'teacher': lesson.teacher,
            'teacher_id': lesson.teacherId,
            'room': lesson.room,
            'homework': jsonEncode(lesson.homeworks),
            'homework_ids_json': jsonEncode(lesson.homeworkIds),
            'updated_at': now,
            'attachments_json': jsonEncode(
              lesson.attachments.map((a) => a.toJson()).toList(),
            ),
            'student_homework_ids_json': jsonEncode(lesson.studentHomeworkIds),
            'is_ec': lesson.isEc ? 1 : 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  /// Уроки за неделю (monday..monday+6), собранные по дням — тем же
  /// форматом, что и свежий ответ API.
  Future<List<DaySchedule>> loadWeek(int yearId, DateTime monday) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    final rows = await db.query(
      AppDatabase.tableLessons,
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
    );

    final byDate = <String, List<Lesson>>{};
    for (final row in rows) {
      final dateStr = row['date'] as String;
      byDate
          .putIfAbsent(dateStr, () => [])
          .add(
            Lesson(
              id: row['id'] as int?,
              startTime: row['start_time'] as String,
              endTime: row['end_time'] as String,
              subject: row['subject'] as String,
              subjectId: row['subject_id'] as int?,
              teacher: row['teacher'] as String?,
              teacherId: row['teacher_id'] as int?,
              room: row['room'] as String?,
              homeworks: Lesson.decodeHomeworks(row['homework'] as String?),
              homeworkIds: _decodeIds(row['homework_ids_json']),
              attachments: HomeworkAttachment.listFromJsonString(
                row['attachments_json'],
              ),
              studentHomeworkIds: _decodeIds(row['student_homework_ids_json']),
              isEc: (row['is_ec'] as int? ?? 0) == 1,
            ),
          );
    }

    return List.generate(6, (i) {
      final day = monday.add(Duration(days: i));
      final lessons = byDate[isoDate(day)] ?? <Lesson>[];
      lessons.sort((a, b) => a.startTime.compareTo(b.startTime));
      return DaySchedule(date: day, lessons: lessons);
    });
  }

  Future<DateTime?> lastUpdated(int yearId, DateTime monday) async {
    final db = await AppDatabase.instance.database;
    final sunday = monday.add(const Duration(days: 6));
    return lastUpdatedAt(
      db,
      AppDatabase.tableLessons,
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
    );
  }

  static List<int> _decodeIds(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<num>()
          .map((e) => e.toInt())
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
