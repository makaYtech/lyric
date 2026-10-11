import 'dart:convert';

import '../../models/grade_slice.dart';
import '../../models/subject_grade.dart';
import 'app_database.dart';

/// Оценки сравниваются на уровне (предмет, период, вид работы):
/// это самый мелкий разрез, который реально приходит из API одним
/// списком (marks[].values[]). Если список оценок внутри такого среза
/// отличается от того, что было сохранено — это и есть "изменение":
/// пишем старую версию в grade_history, помечаем срез changed=1.
///
/// Даты, комментарии и веса сохраняются параллельно grades — по индексу.
/// Если у среза изменились только даты/комменты/веса, а сами оценки те же,
/// срез не помечается changed (UI это не интересно), но значения
/// в БД всё равно обновляются.
class GradesDao {
  Future<void> sync(int yearId, List<SubjectGrade> subjects) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final subject in subjects) {
        for (final period in subject.periods) {
          for (final wt in period.workTypes) {
            final key = _key(yearId, subject.name, period.name, wt.workType);
            final newJson = jsonEncode(wt.grades);
            final newDates = jsonEncode(
              wt.dates.map((d) => d?.toIso8601String()).toList(),
            );
            final newComments = jsonEncode(wt.comments);
            final newWeights = jsonEncode(wt.weights);

            final existing = await txn.query(
              AppDatabase.tableGrades,
              where: 'key = ?',
              whereArgs: [key],
              limit: 1,
            );

            if (existing.isEmpty) {
              await txn.insert(AppDatabase.tableGrades, {
                'key': key,
                'year_id': yearId,
                'subject': subject.name,
                'period': period.name,
                'work_type': wt.workType,
                'grades_json': newJson,
                'dates_json': newDates,
                'comments_json': newComments,
                'weights_json': newWeights,
                'updated_at': now,
                'changed': 0,
              });
              continue;
            }

            final oldJson = existing.first['grades_json'] as String;
            final gradesChanged = oldJson != newJson;

            if (gradesChanged) {
              await txn.insert(AppDatabase.tableGradeHistory, {
                'key': key,
                'old_grades_json': oldJson,
                'changed_at': now,
              });
            }

            await txn.update(
              AppDatabase.tableGrades,
              {
                'grades_json': newJson,
                'dates_json': newDates,
                'comments_json': newComments,
                'weights_json': newWeights,
                'updated_at': now,
                if (gradesChanged) 'changed': 1,
              },
              where: 'key = ?',
              whereArgs: [key],
            );
          }
        }
      }
    });
  }

  Future<List<GradeSlice>> loadCurrent(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableGrades,
      where: 'year_id = ?',
      whereArgs: [yearId],
    );
    return rows.map(_sliceFromRow).toList();
  }

  Future<List<GradeHistoryEntry>> historyFor(
    int yearId,
    String subject,
    String period,
    String workType,
  ) async {
    final db = await AppDatabase.instance.database;
    final key = _key(yearId, subject, period, workType);
    final rows = await db.query(
      AppDatabase.tableGradeHistory,
      where: 'key = ?',
      whereArgs: [key],
      orderBy: 'changed_at DESC',
    );
    return rows
        .map(
          (r) => GradeHistoryEntry(
            grades: (jsonDecode(r['old_grades_json'] as String) as List)
                .whereType<num>()
                .map((e) => e.toInt())
                .toList(),
            changedAt: DateTime.parse(r['changed_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> acknowledge(
    int yearId,
    String subject,
    String period,
    String workType,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      AppDatabase.tableGrades,
      {'changed': 0},
      where: 'key = ?',
      whereArgs: [_key(yearId, subject, period, workType)],
    );
  }

  Future<DateTime?> lastUpdated(int yearId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      AppDatabase.tableGrades,
      columns: ['updated_at'],
      where: 'year_id = ?',
      whereArgs: [yearId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  GradeSlice _sliceFromRow(Map<String, dynamic> r) => GradeSlice(
    key: r['key'] as String,
    subject: r['subject'] as String,
    period: r['period'] as String,
    workType: r['work_type'] as String,
    grades: _decodeGrades(r['grades_json']),
    dates: _decodeDates(r['dates_json']),
    comments: _decodeComments(r['comments_json']),
    weights: _decodeWeights(r['weights_json']),
    updatedAt: DateTime.parse(r['updated_at'] as String),
    changed: (r['changed'] as int) == 1,
  );

  static List<int> _decodeGrades(Object? raw) {
    if (raw is! String) return const [];
    return (jsonDecode(raw) as List)
        .whereType<num>()
        .map((e) => e.toInt())
        .toList();
  }

  static List<DateTime?> _decodeDates(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((d) => d is String ? DateTime.tryParse(d) : null)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String?> _decodeComments(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((c) => c is String ? c : null).toList();
    } catch (_) {
      return const [];
    }
  }

  static List<int?> _decodeWeights(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((w) => w is num ? w.toInt() : null).toList();
    } catch (_) {
      return const [];
    }
  }

  String _key(int yearId, String subject, String period, String workType) =>
      '$yearId|$subject|$period|$workType';
}
