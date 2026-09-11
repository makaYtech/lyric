class WorkTypeGrades {
  final String workType;
  final List<int> grades;

  const WorkTypeGrades({required this.workType, required this.grades});

  double? get average {
    if (grades.isEmpty) return null;
    return grades.reduce((a, b) => a + b) / grades.length;
  }

  Map<String, dynamic> toJson() => {
    'work_type': workType,
    'grades': grades,
  };

  factory WorkTypeGrades.fromJson(Map<String, dynamic> json) {
    final raw = json['grades'] as List<dynamic>? ?? const [];
    return WorkTypeGrades(
      workType: json['work_type'] as String? ?? '—',
      grades: raw.whereType<num>().map((e) => e.toInt()).toList(),
    );
  }
}

/// Оценки за один период (полугодие / триместр / семестр).
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

  factory PeriodGrades.fromJson(Map<String, dynamic> json) {
    final rawWorkTypes = json['work_types'] as List<dynamic>? ?? const [];
    double? avg;
    final rawAvg = json['api_average'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return PeriodGrades(
      name: json['name'] as String? ?? '—',
      workTypes: rawWorkTypes
          .whereType<Map<String, dynamic>>()
          .map(WorkTypeGrades.fromJson)
          .toList(),
      apiAverage: avg,
    );
  }
}

class SubjectGrade {
  final String name;
  final List<PeriodGrades> periods;
  final double? apiAverage;

  const SubjectGrade({
    required this.name,
    required this.periods,
    this.apiAverage,
  });

  double? get average {
    if (apiAverage != null && apiAverage! > 0) return apiAverage;
    final all = allGrades;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a + b) / all.length;
  }

  List<int> get allGrades => periods.expand((p) => p.allGrades).toList();

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
  };

  factory SubjectGrade.fromJson(Map<String, dynamic> json) {
    final name = json['subject_name'] as String? ?? '—';

    final periodsRaw = json['periods'] as List<dynamic>? ?? const [];
    final periods = <PeriodGrades>[];

    for (final p in periodsRaw.whereType<Map<String, dynamic>>()) {
      final periodName = p['name'] as String? ?? '—';
      final byWorkType = <String, List<int>>{};

      final marks = p['marks'] as List<dynamic>? ?? const [];
      for (final m in marks.whereType<Map<String, dynamic>>()) {
        final workType = m['control_form_name'] as String? ?? 'Прочее';
        final values = m['values'] as List<dynamic>? ?? const [];
        for (final v in values.whereType<Map<String, dynamic>>()) {
          final grade = (v['five'] as num?)?.toInt();
          if (grade != null) {
            byWorkType.putIfAbsent(workType, () => []).add(grade);
          }
        }
      }

      double? periodAvg;
      final rawPeriodAvg = p['avg_five'];
      if (rawPeriodAvg is String) periodAvg = double.tryParse(rawPeriodAvg);
      if (rawPeriodAvg is num) periodAvg = rawPeriodAvg.toDouble();

      periods.add(PeriodGrades(
        name: periodName,
        workTypes: byWorkType.entries
            .map((e) => WorkTypeGrades(workType: e.key, grades: e.value))
            .toList(),
        apiAverage: periodAvg,
      ));
    }

    double? avg;
    final rawAvg = json['avg_five'];
    if (rawAvg is String) avg = double.tryParse(rawAvg);
    if (rawAvg is num) avg = rawAvg.toDouble();

    return SubjectGrade(
      name: name,
      periods: periods,
      apiAverage: avg,
    );
  }
}