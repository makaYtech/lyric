import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/day_schedule.dart';
import '../../models/homework_attachment.dart';
import '../../models/lesson.dart';
import '../util/date_time.dart';
import 'app_database.dart';

/// Всё, что связано с расписанием и ДЗ, живёт здесь одной строкой на урок.
/// Никакой истории — расписание переносится/меняется, старое значение
/// никому не интересно, просто перезаписываем по id урока.
class ScheduleDao {
  Future<void> saveWeek(int yearId, List<DaySchedule> days) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // Находим границы недели по первому дню. Если список пустой —
    // сохранять нечего, выходим.
    if (days.isEmpty) return;
    final monday = days.first.date;
    final sunday = monday.add(const Duration(days: 6));

    await db.transaction((txn) async {
      // Перезаписываем неделю целиком: если на сервере урок отменили и
      // он пропал из ответа — в БД он тоже должен пропасть, иначе
      // оффлайн-режим покажет фантом. См. MarksDao.saveWeek — там то же.
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

  /// Отдаёт сохранённые уроки за неделю (monday..monday+6), уже
  /// собранными по дням — тем же форматом, что и свежий ответ API.
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
              attachments: _decodeAttachments(row['attachments_json']),
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
    final rows = await db.query(
      AppDatabase.tableLessons,
      columns: ['updated_at'],
      where: 'year_id = ? AND date BETWEEN ? AND ?',
      whereArgs: [yearId, isoDate(monday), isoDate(sunday)],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
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

  static List<HomeworkAttachment> _decodeAttachments(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(HomeworkAttachment.fromJson)
          .where((a) => a.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
