import 'package:sqflite/sqflite.dart';

import '../../models/homework.dart';
import 'app_database.dart';
import 'dart:convert';
import '../../models/homework_attachment.dart';

/// ДЗ живут по годам: перезаписываем весь год разом. Так проще, чем
/// по неделям — ДЗ не так много, а диапазон у нас всегда один и тот же
/// (сентябрь..август), поэтому delete+insert не страшен.
class HomeworkDao {
  Future<void> saveAll(int yearId, List<Homework> homeworks) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableHomeworks,
        where: 'year_id = ?',
        whereArgs: [yearId],
      );

      final batch = txn.batch();
      for (final h in homeworks) {
        if (h.id == 0) continue;
        batch.insert(
          AppDatabase.tableHomeworks,
          {
            'id': h.id,
            'year_id': yearId,
            'homework_id': h.homeworkId,
            'entry_id': h.entryId,
            'description': h.description,
            'due_date': h.dueDate?.toIso8601String(),
            'assigned_at': h.assignedAt?.toIso8601String(),
            'created_at': h.createdAt?.toIso8601String(),
            'subject_name': h.subjectName,
            'subject_id': h.subjectId,
            'teacher_id': h.teacherId,
            'group_id': h.groupId,
            'is_required': h.isRequired ? 1 : 0,
            'mark_required': h.markRequired ? 1 : 0,
            'updated_at': now,
            'teacher_name': h.teacherName,
            'attachments_json': jsonEncode(
              h.attachments.map((a) => a.toJson()).toList(),
            ),
            'my_attachments_json': jsonEncode(
              h.myAttachments.map((a) => a.toJson()).toList(),
            ),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Homework>> loadAll(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableHomeworks,
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'due_date ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<DateTime?> lastUpdated(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableHomeworks,
      columns: ['updated_at'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  Homework _fromRow(Map<String, dynamic> r) => Homework(
    id: r['id'] as int,
    homeworkId: r['homework_id'] as int? ?? 0,
    entryId: r['entry_id'] as int? ?? 0,
    description: r['description'] as String? ?? '',
    dueDate: _date(r['due_date']),
    assignedAt: _date(r['assigned_at']),
    createdAt: _date(r['created_at']),
    subjectName: r['subject_name'] as String?,
    subjectId: r['subject_id'] as int?,
    teacherId: r['teacher_id'] as int?,
    groupId: r['group_id'] as int?,
    isRequired: (r['is_required'] as int? ?? 0) == 1,
    markRequired: (r['mark_required'] as int? ?? 0) == 1,
    teacherName: r['teacher_name'] as String?,
    attachments: _decodeAttachments(r['attachments_json']),
    myAttachments: _decodeAttachments(r['my_attachments_json']),
  );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

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