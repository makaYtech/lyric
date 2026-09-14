/// interval_id в «Моей школе» — это «<номер недели><год>»:
///   372026 = 37-я неделя 2026 года.
/// По нему группируются ДЗ, оценки, уроки. Запрашиваем сразу несколько
/// подряд, чтобы получить данные за нужный период.
class IntervalHelper {
  IntervalHelper._();

  static String forDate(DateTime date) {
    final week = _isoWeek(date);
    return '${week.toString().padLeft(2, '0')}${date.year}';
  }

  /// Текущая неделя + N-1 предыдущих, от новой к старой.
  static List<String> lastWeeks(int count) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      return forDate(now.subtract(Duration(days: 7 * i)));
    });
  }

  static int _isoWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final dayOfYear = d.difference(DateTime(d.year, 1, 1)).inDays + 1;
    var woy = (dayOfYear - d.weekday + 10) ~/ 7;
    if (woy < 1) {
      woy = _isoWeeksInYear(d.year - 1);
    } else if (woy > _isoWeeksInYear(d.year)) {
      woy = 1;
    }
    return woy;
  }

  static int _isoWeeksInYear(int year) {
    final p = (year + year ~/ 4 - year ~/ 100 + year ~/ 400) % 7;
    return p == 4 || p == 3 ? 53 : 52;
  }
}