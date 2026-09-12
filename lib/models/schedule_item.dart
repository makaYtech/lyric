import '../core/util/date_time.dart';

/// Один урок из /jersey/api/schedule_items.
class ScheduleItem {
  final int id;
  final String subjectName;
  /// subject_id — нужен на будущее, если матч по id урока не сработает.
  final int? subjectId;
  final int? teacherId;
  final DateTime date;
  final String beginTime; // "HH:mm"
  final int durationMinutes;
  final List<int> homeworkIds;
  final int? roomId;
  final String? roomName;

  const ScheduleItem({
    required this.id,
    required this.subjectName,
    this.subjectId,
    required this.teacherId,
    required this.date,
    required this.beginTime,
    required this.durationMinutes,
    required this.homeworkIds,
    this.roomId,
    this.roomName,
  });

  String get endTime {
    final parts = beginTime.split(':');
    if (parts.length != 2) return beginTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final total = h * 60 + m + durationMinutes;
    return hhmm((total ~/ 60) % 24, total % 60);
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'] as List<dynamic>? ?? const [];
    final rawTime = json['time'] as List<dynamic>? ?? const [];
    final rawHw = json['homeworks_to_give'] as List<dynamic>? ?? const [];

    return ScheduleItem(
      id: json['id'] as int? ?? 0,
      subjectName: json['subject_name'] as String? ?? '—',
      subjectId: json['subject_id'] as int?,
      teacherId: json['teacher_id'] as int?,
      date: dateFromJsonList(rawDate),
      beginTime: timeFromJsonList(rawTime),
      durationMinutes: json['duration'] as int? ?? 45,
      homeworkIds: rawHw
          .whereType<Map<String, dynamic>>()
          .map((e) => e['id'])
          .whereType<int>()
          .toList(),
      roomId: json['room_id'] as int?,
      roomName: json['room_name'] as String?,
    );
  }
}