/// Модели для срезов оценок в БД.
///
/// Раньше жили прямо в grades_dao.dart, но это именно модели данных,
/// а не логика доступа — переехали сюда, чтобы DAO был только про SQL.
library;

/// Текущий срез оценок по одному разрезу (предмет+период+вид работы),
/// плюс признак того, что с прошлой синхронизации список изменился.
class GradeSlice {
  final String key;
  final String subject;
  final String period;
  final String workType;
  final List<int> grades;
  final List<DateTime?> dates;
  final List<String?> comments;
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
    required this.updatedAt,
    required this.changed,
  });
}

/// Старая версия среза — что было ДО последнего изменения, и когда
/// оно произошло.
class GradeHistoryEntry {
  final List<int> grades;
  final DateTime changedAt;

  const GradeHistoryEntry({required this.grades, required this.changedAt});
}
