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
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _fileName = 'epos_cache.db';
  static const _version = 3;

  static const tableLessons = 'lessons';
  static const tableGrades = 'grades';
  static const tableGradeHistory = 'grade_history';
  static const tableMarks = 'marks';

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
      },
    );
  }

  Future<void> _createAll(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLessons (
        id INTEGER PRIMARY KEY,
        year_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        subject TEXT NOT NULL,
        teacher TEXT,
        room TEXT,
        homework TEXT,
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
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marks_week ON $tableMarks(year_id, date)',
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete(tableLessons);
    await db.delete(tableGrades);
    await db.delete(tableGradeHistory);
    await db.delete(tableMarks);
  }
}