import '../core/util/date_time.dart';

class WorkTypeGrades {
  final String workType;
  final List<int> grades;
  /// Дата каждой оценки (по индексу, параллельно grades).
  /// null, если API не прислал дату конкретной оценки.
  final List<DateTime?> dates;
  /// Комментарий учителя, по индексу параллельно grades.
  /// null, если комментария нет.
  final List<String?> comments;

  const WorkTypeGrades({
    required this.workType,
    required this.grades,
    this.dates = const [],
    this.comments = const [],
  });

  DateTime? dateAt(int i) =>
      i >= 0 && i < dates.length ? dates[i] : null;

  String? commentAt(int i) {
    if (i < 0 || i >= comments.length) return null;
    final c = comments[i];
    if (c == null) return null;
    final t = c.trim();
    return t.isEmpty ? null : t;
  }

  double? get average {
    if (grades.isEmpty) return null;
    return grades.reduce((a, b) => a + b) / grades.length;
  }

  Map<String, dynamic> toJson() => {
    'work_type': workType,
    'grades': grades,
    'dates': dates.map((d) => d?.toIso8601String()).toList(),
    'comments': comments,
  };

  factory WorkTypeGrades.fromCache(Map<String, dynamic> json) {
    final raw = json['grades'] as List<dynamic>? ?? const [];
    final rawDates = json['dates'] as List<dynamic>? ?? const [];
    final rawComments = json['comments'] as List<dynamic>? ?? const [];
    return WorkTypeGrades(
      workType: json['work_type'] as String? ?? '—',
      grades: raw.whereType<num>().map((e) => e.toInt()).toList(),
      dates: rawDates
          .map((d) => d is String ? DateTime.tryParse(d) : null)
          .toList(),
      comments: rawComments.map((c) => c is String ? c : null).toList(),
    );
  }
}

class PeriodGrades {
  final String name;
  final List<WorkTypeGrades> workTypes;
  final double? apiAverage;

  const PeriodGrades({
    required this.name,
    required this.workTypes,
    this.apiAverage,
  });

  List<int> get allGrades => workTypes.expand((w) => w.grades).toList();
  List<DateTime?> get allDates => workTypes.expand((w) => w.dates).toList();
  List<String?> get allComments =>
      workTypes.expand((w) => w.comments).toList();

  double? get average {
    if (apiAverage != null && apiAverage! > 0) return apiAverage;
    final all = allGrades;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a + b) / all.length;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'work_types': workTypes.map((w) => w.toJson()).toList(),
    'api_average': apiAverage,
  };

  factory PeriodGrades.fromCache(Map<String, dynamic> json) {
    final rawWorkTypes = json['work_types'] as List<dynamic>? ?? const [];
    double? avg;
    final rawAvg = json['api_average'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return PeriodGrades(
      name: json['name'] as String? ?? '—',
      workTypes: rawWorkTypes
          .whereType<Map<String, dynamic>>()
          .map(WorkTypeGrades.fromCache)
          .toList(),
      apiAverage: avg,
    );
  }

  /// Из ответа /reports/api/progress/json.
  factory PeriodGrades.fromApi(Map<String, dynamic> json) {
    final byWorkType = <String, List<int>>{};
    final datesByWorkType = <String, List<DateTime?>>{};
    final commentsByWorkType = <String, List<String?>>{};
    final marks = json['marks'] as List<dynamic>? ?? const [];

    for (final m in marks.whereType<Map<String, dynamic>>()) {
      final workType = m['control_form_name'] as String? ?? 'Прочее';
      final values = m['values'] as List<dynamic>? ?? const [];

      // В /core/api/marks created_at и comment висят на уровне записи,
      // а не отдельного значения. Здесь структура другая, но по аналогии
      // пробуем сначала на уровне значения, потом на уровне marks[].
      final formDate = parseEposDateTime(
        m['created_at'] ?? m['date'] ?? m['mark_date'],
      );
      final formComment = _asString(m['comment']);

      for (final v in values.whereType<Map<String, dynamic>>()) {
        final grade = _extractGrade(v);
        if (grade == null) continue;

        byWorkType.putIfAbsent(workType, () => []).add(grade);

        final vDate = parseEposDateTime(
          v['created_at'] ?? v['date'] ?? v['mark_date'],
        );
        datesByWorkType
            .putIfAbsent(workType, () => [])
            .add(vDate ?? formDate);

        final vComment = _asString(v['comment']);
        commentsByWorkType
            .putIfAbsent(workType, () => [])
            .add(vComment ?? formComment);
      }
    }

    double? avg;
    final rawAvg = json['avg_five'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return PeriodGrades(
      name: json['name'] as String? ?? '—',
      workTypes: byWorkType.entries
          .map((e) => WorkTypeGrades(
        workType: e.key,
        grades: e.value,
        dates: datesByWorkType[e.key] ?? const [],
        comments: commentsByWorkType[e.key] ?? const [],
      ))
          .toList(),
      apiAverage: avg,
    );
  }

  /// Значение оценки: обычно на верхнем уровне `five`, но на всякий
  /// случай пробуем и вложенный `grade.five`.
  static int? _extractGrade(Map<String, dynamic> v) {
    final direct = v['five'];
    if (direct is num) return direct.toInt();
    final nested = v['grade'];
    if (nested is Map<String, dynamic>) {
      final five = nested['five'];
      if (five is num) return five.toInt();
    }
    return null;
  }

  static String? _asString(Object? raw) {
    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }
}

class SubjectGrade {
  final String name;
  final List<PeriodGrades> periods;
  final double? apiAverage;

  /// Числовой id предмета из API. Нужен, чтобы матчить оценки из
  /// /core/api/marks (у них есть только subject_id, без имени) с
  /// типами работ из /reports/api/progress/json.
  final int? subjectId;

  const SubjectGrade({
    required this.name,
    required this.periods,
    this.apiAverage,
    this.subjectId,
  });

  double? get average {
    if (apiAverage != null && apiAverage! > 0) return apiAverage;
    final all = allGrades;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a + b) / all.length;
  }

  List<int> get allGrades => periods.expand((p) => p.allGrades).toList();
  List<DateTime?> get allDates => periods.expand((p) => p.allDates).toList();
  List<String?> get allComments =>
      periods.expand((p) => p.allComments).toList();

  PeriodGrades? periodByName(String name) {
    for (final p in periods) {
      if (p.name == name) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'periods': periods.map((p) => p.toJson()).toList(),
    'api_average': apiAverage,
    'subject_id': subjectId,
  };

  factory SubjectGrade.fromCache(Map<String, dynamic> json) {
    final rawPeriods = json['periods'] as List<dynamic>? ?? const [];
    double? avg;
    final rawAvg = json['api_average'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return SubjectGrade(
      name: json['name'] as String? ?? '—',
      periods: rawPeriods
          .whereType<Map<String, dynamic>>()
          .map(PeriodGrades.fromCache)
          .toList(),
      apiAverage: avg,
      subjectId: json['subject_id'] as int?,
    );
  }

  /// Из ответа /reports/api/progress/json.
  factory SubjectGrade.fromApi(Map<String, dynamic> json) {
    final rawPeriods = json['periods'] as List<dynamic>? ?? const [];
    double? avg;
    final rawAvg = json['avg_five'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return SubjectGrade(
      name: json['subject_name'] as String? ?? '—',
      periods: rawPeriods
          .whereType<Map<String, dynamic>>()
          .map(PeriodGrades.fromApi)
          .toList(),
      apiAverage: avg,
      subjectId: json['subject_id'] as int?,
    );
  }
}