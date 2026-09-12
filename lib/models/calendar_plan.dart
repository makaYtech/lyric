import '../core/util/date_time.dart';

/// Ответ /jersey/api/calendar_plans — уроки, сгруппированные по группам.
/// Из каждой группы берём lessons[], чтобы собрать DaySchedule.
class CalendarPlan {
  final int groupId;
  final String groupName;
  final List<CalendarLesson> lessons;

  const CalendarPlan({
    required this.groupId,
    required this.groupName,
    required this.lessons,
  });

  factory CalendarPlan.fromJson(Map<String, dynamic> json) {
    final raw = json['lessons'] as List<dynamic>? ?? const [];
    return CalendarPlan(
      groupId: json['group_id'] as int? ?? 0,
      groupName: json['group_name'] as String? ?? '—',
      lessons: raw
          .whereType<Map<String, dynamic>>()
          .map(CalendarLesson.fromJson)
          .toList(),
    );
  }
}

class CalendarLesson {
  final DateTime date;
  final String beginTime; // "HH:mm"
  final int? ordinal;
  final int? studyOrdinal;
  final String? homework;

  const CalendarLesson({
    required this.date,
    required this.beginTime,
    this.ordinal,
    this.studyOrdinal,
    this.homework,
  });

  factory CalendarLesson.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as List<dynamic>? ?? const [];
    final rawTime = json['begin_time'] as List<dynamic>? ?? const [];

    return CalendarLesson(
      date: dateFromJsonList(rawDate),
      beginTime: rawTime.length >= 2 ? timeFromJsonList(rawTime) : '',
      ordinal: json['ordinal'] as int?,
      studyOrdinal: json['study_ordinal'] as int?,
      homework: _extractHomework(json['homeworks_to_give']),
    );
  }

  /// homeworks_to_give — массив объектов; берём первый непустой текст.
  static String? _extractHomework(dynamic raw) {
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final text = item['homework'] as String? ??
            item['text'] as String? ??
            item['name'] as String?;
        if (text != null && text.trim().isNotEmpty) return text.trim();
      }
    }
    return null;
  }
}