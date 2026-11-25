/// Модели для срезов оценок в БД.
library;

class GradeSlice {
  final String key;
  final String subject;
  final String period;
  final String workType;
  final List<int> grades;
  final List<DateTime?> dates;
  final List<String?> comments;

  /// Вес каждой оценки, параллельно grades. 1 или null — обычная.
  final List<int?> weights;
  final DateTime updatedAt;
  final bool changed;

  const GradeSlice({
    required this.key,
    required this.subject,
    required this.period,
    required this.workType,
    required this.grades,
    required this.dates,
    required this.comments,
    required this.weights,
    required this.updatedAt,
    required this.changed,
  });
}

class GradeHistoryEntry {
  final List<int> grades;
  final DateTime changedAt;

  const GradeHistoryEntry({required this.grades, required this.changedAt});
}
