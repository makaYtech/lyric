import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Единственное соединение с локальной SQLite-базой.
///
/// lessons       — расписание + дз (текущее состояние, без истории).
/// grades        — оценки: текущий срез по разрезу
///                  (год, предмет, период, вид работы) + даты и комменты.
/// grade_history — прошлые версии grades.grades_json.
/// marks         — индивидуальные оценки из /core/api/marks,
///                  нужны расписанию: точки с временем получения.
/// homeworks     — ДЗ по году из /core/api/student_homeworks.
/// teachers      — учителя школы из /core/api/teacher_profiles
///                  (с обогащением через /core/api/rooms).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'epos_cache.db';
  static const _version = 11;

  static const tableLessons = 'lessons';
  static const tableGrades = 'grades';
  static const tableGradeHistory = 'grade_history';
  static const tableMarks = 'marks';
  static const tableHomeworks = 'homeworks';
  static const tableTeachers = 'teachers';

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database async {
    final ready = _db;
    if (ready != null) return ready;
    final inFlight = _opening;
    if (inFlight != null) return inFlight;

    final fut = _open();
    _opening = fut;
    try {
      final db = await fut;
      _db = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    try {
      return await _openAt(path);
    } catch (_) {
      // База битая или недосоздана (например, схема упала на полпути).
      // Кэш — не ценные данные, сносим файл и создаём заново: это лучше,
      // чем навсегда неработающее приложение.
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return _openAt(path);
    }
  }

  Future<Database> _openAt(String path) {
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, _) async => _createAll(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v1 хранил всё в kv_cache — не жалко, дропаем и создаём заново.
          await db.execute('DROP TABLE IF EXISTS kv_cache');
          await _createAll(db);
          return;
        }
        if (oldVersion < 3) {
          // v2 → v3: даты и комментарии для оценок + таблица marks.
          await db.execute(
            'ALTER TABLE $tableGrades ADD COLUMN dates_json TEXT',
          );
          await db.execute(
            'ALTER TABLE $tableGrades ADD COLUMN comments_json TEXT',
          );
          await _createMarksTable(db);
        }
        if (oldVersion < 6) {
          // homeworks успела пожить в нескольких несовместимых схемах.
          // ALTER-ми это чинить бессмысленно — дропаем и создаём заново.
          await db.execute('DROP TABLE IF EXISTS $tableHomeworks');
          await _createHomeworksTable(db);
        }
        if (oldVersion < 7) {
          await _createTeachersTable(db);
        }
        if (oldVersion < 9) {
          // lessons получили teacher_id (числовой id учителя) — нужно,
          // чтобы понять, какие учителя ведут у текущего ученика.
          if (!await _columnExists(db, tableLessons, 'teacher_id')) {
            await db.execute(
              'ALTER TABLE $tableLessons ADD COLUMN teacher_id INTEGER',
            );
          }
        }
        if (oldVersion < 10) {
          if (!await _columnExists(db, tableLessons, 'attachments_json')) {
            await db.execute(
              "ALTER TABLE $tableLessons "
                  "ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
          if (!await _columnExists(db, tableHomeworks, 'attachments_json')) {
            await db.execute(
              "ALTER TABLE $tableHomeworks "
                  "ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
        }
        if (oldVersion < 11) {
          if (!await _columnExists(
              db, tableLessons, 'student_homework_ids_json')) {
            await db.execute(
              "ALTER TABLE $tableLessons ADD COLUMN "
                  "student_homework_ids_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
          if (!await _columnExists(db, tableHomeworks, 'my_attachments_json')) {
            await db.execute(
              "ALTER TABLE $tableHomeworks ADD COLUMN "
                  "my_attachments_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
        }
      },
    );
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => r['name'] == column);
  }

  Future<void> _createAll(Database db) async {
    // ВНИМАНИЕ: никаких висячих запятых перед закрывающей скобкой —
    // SQLite отвечает «near ")": syntax error», onCreate падает целиком,
    // и приложение остаётся вообще без базы (проявляется только на
    // чистой установке, потому что onCreate больше нигде не вызывается).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLessons (
        id INTEGER PRIMARY KEY,
        year_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        subject TEXT NOT NULL,
        teacher TEXT,
        teacher_id INTEGER,
        room TEXT,
        homework TEXT,
        attachments_json TEXT NOT NULL DEFAULT '[]',
        student_homework_ids_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_lessons_date ON $tableLessons(year_id, date)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableGrades (
        key TEXT PRIMARY KEY,
        year_id INTEGER NOT NULL,
        subject TEXT NOT NULL,
        period TEXT NOT NULL,
        work_type TEXT NOT NULL,
        grades_json TEXT NOT NULL,
        dates_json TEXT,
        comments_json TEXT,
        updated_at TEXT NOT NULL,
        changed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grades_year ON $tableGrades(year_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableGradeHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        old_grades_json TEXT NOT NULL,
        changed_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grade_history_key ON $tableGradeHistory(key)',
    );

    await _createMarksTable(db);
    await _createHomeworksTable(db);
    await _createTeachersTable(db);
  }

  Future<void> _createMarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableMarks (
        id INTEGER PRIMARY KEY,
        year_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        value INTEGER NOT NULL,
        subject_id INTEGER,
        created_at TEXT,
        schedule_lesson_id INTEGER,
        group_id INTEGER,
        teacher_id INTEGER,
        work_type TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marks_week ON $tableMarks(year_id, date)',
    );
  }

  /// Одна-единственная схема. Раньше тут стояли два CREATE подряд, и
  /// из-за IF NOT EXISTS выигрывал первый — без attachments_json, отчего
  /// вставка ДЗ падала на «no column named attachments_json».
  Future<void> _createHomeworksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableHomeworks (
        id INTEGER PRIMARY KEY,
        year_id INTEGER NOT NULL,
        homework_id INTEGER NOT NULL,
        entry_id INTEGER NOT NULL,
        description TEXT NOT NULL,
        due_date TEXT,
        assigned_at TEXT,
        created_at TEXT,
        subject_name TEXT,
        subject_id INTEGER,
        teacher_id INTEGER,
        teacher_name TEXT,
        group_id INTEGER,
        is_required INTEGER NOT NULL DEFAULT 0,
        mark_required INTEGER NOT NULL DEFAULT 0,
        attachments_json TEXT NOT NULL DEFAULT '[]',
        my_attachments_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_homeworks_year ON $tableHomeworks(year_id, due_date)',
    );
  }

  Future<void> _createTeachersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableTeachers (
        id INTEGER NOT NULL,
        year_id INTEGER NOT NULL,
        full_name TEXT NOT NULL,
        workload INTEGER NOT NULL DEFAULT 0,
        hired_at TEXT,
        is_newcomer INTEGER NOT NULL DEFAULT 0,
        building_name TEXT,
        building_address TEXT,
        roles_json TEXT NOT NULL DEFAULT '[]',
        subjects_json TEXT NOT NULL DEFAULT '[]',
        managed_classes_json TEXT NOT NULL DEFAULT '[]',
        rooms_json TEXT NOT NULL DEFAULT '[]',
        owned_room_ids_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL,
        PRIMARY KEY (id, year_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_teachers_year ON $tableTeachers(year_id)',
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(tableLessons);
    await db.delete(tableGrades);
    await db.delete(tableGradeHistory);
    await db.delete(tableMarks);
    await db.delete(tableHomeworks);
    await db.delete(tableTeachers);
  }
}