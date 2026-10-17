/// Общие утилиты для дат/времени ЭПОСа.
///
/// ЭПОС отдаёт даты минимум четырьмя способами:
/// - ISO 8601 ("2026-09-07T11:43:00.000");
/// - "dd.MM.yyyy HH:mm" для ручек, принимающих даты параметром;
/// - списком [y, m, d] или [y, m, d, h, mi, s] (schedule_items, calendar_plans);
/// - отдельным списком времени [h, mi] (schedule_items.begin_time).
///
/// Здесь — единые точки входа для всех этих случаев. Раньше логика была
/// продублирована в Mark, ScheduleItem, CalendarLesson и сервисах.
library;

/// "2026-09-07" — формат, который ждут schedule_items и БД.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "07.09.2026" — формат, который ждёт marks и student_homeworks.
String dotDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.'
    '${d.month.toString().padLeft(2, '0')}.'
    '${d.year}';

/// "HH:mm" из пары чисел. "09:05", а не "9:5".
String hhmm(int h, int m) => '${_two(h)}:${_two(m)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// Дата из списка, как её отдаёт jersey/api: [y, m, d] или [y, m, d, h, mi, s].
/// Битые/короткие списки деградируют до 1970-01-01 — как и раньше делали
/// ScheduleItem и CalendarLesson.
DateTime dateFromJsonList(List<dynamic> raw) => DateTime(
  raw.isNotEmpty ? _asInt(raw[0]) ?? 1970 : 1970,
  raw.length > 1 ? _asInt(raw[1]) ?? 1 : 1,
  raw.length > 2 ? _asInt(raw[2]) ?? 1 : 1,
);

/// "HH:mm" из списка [h, mi], как отдаёт schedule_items.
/// Пустой/короткий список → "00:00".
String timeFromJsonList(List<dynamic> raw) {
  if (raw.length < 2) return '00:00';
  return hhmm(_asInt(raw[0]) ?? 0, _asInt(raw[1]) ?? 0);
}

int? _asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// Универсальный парсер даты-времени ЭПОСа.
/// Понимает:
/// - "07.09.2026 11:43" / "07.09.2026 11:43:12" / "07.09.2026";
/// - ISO 8601 ("2026-09-07T11:43:00.000");
/// - списки [y, m, d] или [y, m, d, h, mi, s].
/// (Переехало из Mark.parseEposDateTime.)
DateTime? parseEposDateTime(Object? raw) {
  if (raw == null) return null;

  if (raw is String && raw.trim().isNotEmpty) {
    final s = raw.trim();
    final m = RegExp(
      r'^(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(s);
    if (m != null) {
      final d = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final y = int.tryParse(m.group(3)!);
      if (d == null || mo == null || y == null) return null;
      final h = int.tryParse(m.group(4) ?? '0') ?? 0;
      final mi = int.tryParse(m.group(5) ?? '0') ?? 0;
      final sec = int.tryParse(m.group(6) ?? '0') ?? 0;
      return DateTime(y, mo, d, h, mi, sec);
    }
    return DateTime.tryParse(s);
  }

  if (raw is List && raw.length >= 3) {
    final y = _asInt(raw[0]);
    final mo = _asInt(raw[1]);
    final d = _asInt(raw[2]);
    if (y == null || mo == null || d == null) return null;
    final h = raw.length > 3 ? _asInt(raw[3]) ?? 0 : 0;
    final mi = raw.length > 4 ? _asInt(raw[4]) ?? 0 : 0;
    final sec = raw.length > 5 ? _asInt(raw[5]) ?? 0 : 0;
    return DateTime(y, mo, d, h, mi, sec);
  }

  return null;
}

/// "07.09.2026" → DateTime(2026, 9, 7)
DateTime? parseEposDate(Object? raw) {
  final dt = parseEposDateTime(raw);
  if (dt == null) return null;
  return DateTime(dt.year, dt.month, dt.day);
}

// ── Нормализация дат (общие операции, ранее дублировались по коду) ──────

/// Только дата, без времени: DateTime(d.year, d.month, d.day).
/// Раньше был локальный `_dayOnly` в ScheduleView / ScheduleOverride.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Понедельник недели, содержащей [d] — то же значение, что `weekStart`
/// в UI. Раньше был локальный `_monday` в ScheduleRepository/Service.
DateTime mondayOf(DateTime d) {
  final monday = d.subtract(Duration(days: d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day);
}

/// Понедельник текущей недели.
/// Раньше был локальный `_currentMonday` в HomeController.
DateTime currentMonday() => mondayOf(DateTime.now());

/// Один и тот же календарный день (без учёта времени).
/// Раньше был локальный `_sameDay` в ScheduleView / _DayStrip.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Учебный год, которому принадлежит дата: сентябрь..август.
/// Возвращает (1 сентября начала, 31 августа конца).
/// Раньше был локальный `_academicYearRange` в HomeController.
(DateTime, DateTime) academicYearRange(DateTime today) {
  final year = today.month >= 9 ? today.year : today.year - 1;
  return (DateTime(year, 9, 1), DateTime(year + 1, 8, 31));
}
