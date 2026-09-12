/// Ответ /core/api/bells_timetables — расписание звонков.
/// Нас интересует только `bells_day_timetables` → `bells`:
/// по study_ordinal находим точное время начала и конца урока.
class BellsTimetable {
  final int id;
  final List<BellsDay> days;

  const BellsTimetable({required this.id, required this.days});

  factory BellsTimetable.fromJson(Map<String, dynamic> json) {
    final rawDays = json['bells_day_timetables'] as List<dynamic>? ?? const [];
    return BellsTimetable(
      id: json['id'] as int? ?? 0,
      days: rawDays
          .whereType<Map<String, dynamic>>()
          .map(BellsDay.fromJson)
          .toList(),
    );
  }
}

class BellsDay {
  final int weekDayId; // 1 = Пн ... 7 = Вс
  final List<Bell> bells;

  const BellsDay({required this.weekDayId, required this.bells});

  factory BellsDay.fromJson(Map<String, dynamic> json) {
    final rawBells = json['bells'] as List<dynamic>? ?? const [];
    return BellsDay(
      weekDayId: json['week_day_id'] as int? ?? 0,
      bells: rawBells
          .whereType<Map<String, dynamic>>()
          .map(Bell.fromJson)
          .toList(),
    );
  }
}

class Bell {
  final int? studyOrdinal;
  final bool isLesson;
  final String beginTime;
  final String endTime;

  const Bell({
    required this.studyOrdinal,
    required this.isLesson,
    required this.beginTime,
    required this.endTime,
  });

  factory Bell.fromJson(Map<String, dynamic> json) => Bell(
    studyOrdinal: json['study_ordinal'] as int?,
    isLesson: json['is_lesson'] as bool? ?? false,
    beginTime: json['begin_time'] as String? ?? '',
    endTime: json['end_time'] as String? ?? '',
  );
}