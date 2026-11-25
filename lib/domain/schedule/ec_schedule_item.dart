import '../../core/util/json.dart';

/// Один урок из /ec/api/ec_schedule_items — внеурочное занятие.
///
/// Отличия от обычного ScheduleItem: subject_name заменён на
/// ec_course_calendar_lesson_name; date/begin_time/end_time — строки;
/// homeworks_to_give/verify — массивы числовых id.
class EcScheduleItem {
  final int id;
  final int ecGroupId;
  final int? teacherId;
  final DateTime date;
  final String beginTime;
  final String endTime;
  final String name;
  final int? ecActivityId;
  final int? courseLessonId;
  final int? roomId;
  final int? buildingId;
  final int? ordinal;
  final List<int> homeworksToGive;
  final List<int> homeworksToVerify;

  const EcScheduleItem({
    required this.id,
    required this.ecGroupId,
    this.teacherId,
    required this.date,
    required this.beginTime,
    required this.endTime,
    required this.name,
    this.ecActivityId,
    this.courseLessonId,
    this.roomId,
    this.buildingId,
    this.ordinal,
    this.homeworksToGive = const [],
    this.homeworksToVerify = const [],
  });

  factory EcScheduleItem.fromJson(Map<String, dynamic> j) => EcScheduleItem(
    id: j.intOr('id', 0),
    ecGroupId: j.intOr('ec_group_id', 0),
    teacherId: j.intOrNull('teacher_id'),
    date: _parseDate(j['date']),
    beginTime: j.str('begin_time'),
    endTime: j.str('end_time'),
    name: j.strOr('ec_course_calendar_lesson_name', '—'),
    ecActivityId: j.intOrNull('ec_activity_id'),
    courseLessonId: j.intOrNull('ec_course_calendar_lesson_id'),
    roomId: j.intOrNull('room_id'),
    buildingId: j.intOrNull('building_id'),
    ordinal: j.intOrNull('ordinal'),
    homeworksToGive: _readIntList(j['homeworks_to_give']),
    homeworksToVerify: _readIntList(j['homeworks_to_verify']),
  );

  static DateTime _parseDate(Object? raw) {
    if (raw is String) {
      final d = DateTime.tryParse(raw);
      if (d != null) return d;
    }
    return DateTime(1970, 1, 1);
  }

  static List<int> _readIntList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<num>().map((e) => e.toInt()).toList();
  }
}
