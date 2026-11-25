import '../../core/util/date_time.dart';
import '../../core/util/json.dart';

/// Один урок из /jersey/api/schedule_items.
class ScheduleItem {
  final int id;
  final String subjectName;
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
    final start = minutesFromHhmm(beginTime);
    if (start == null) return beginTime;
    final total = start + durationMinutes;
    return hhmm((total ~/ 60) % 24, total % 60);
  }

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final rawHw = json.list('homeworks_to_give');

    return ScheduleItem(
      id: json.intOr('id', 0),
      subjectName: json.strOr('subject_name', '—'),
      subjectId: json.intOrNull('subject_id'),
      teacherId: json.intOrNull('teacher_id'),
      date: dateFromJsonList(json.list('date')),
      beginTime: timeFromJsonList(json.list('time')),
      durationMinutes: json.intOr('duration', 45),
      homeworkIds: rawHw
          .whereType<Map<String, dynamic>>()
          .map((e) => e['id'])
          .whereType<int>()
          .toList(),
      roomId: json.intOrNull('room_id'),
      roomName: json['room_name'] as String?,
    );
  }
}
