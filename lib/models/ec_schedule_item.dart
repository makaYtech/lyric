/// Один урок из /ec/api/ec_schedule_items — внеурочное занятие
/// («Разговоры о важном», «Россия — мои горизонты» и т.п.).
///
/// Отличия от обычного ScheduleItem:
///   • subject_name → ec_course_calendar_lesson_name;
///   • date/begin_time/end_time — строки, а не списки [y,m,d]/[h,m];
///   • homeworks_to_give/verify — массивы числовых id, не [{id}];
///   • присутствуют ec_group_id, ec_activity_id, courseLessonId.
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
    id: j['id'] as int? ?? 0,
    ecGroupId: j['ec_group_id'] as int? ?? 0,
    teacherId: j['teacher_id'] as int?,
    date: _parseDate(j['date']),
    beginTime: j['begin_time'] as String? ?? '',
    endTime: j['end_time'] as String? ?? '',
    name: j['ec_course_calendar_lesson_name'] as String? ?? '—',
    ecActivityId: j['ec_activity_id'] as int?,
    courseLessonId: j['ec_course_calendar_lesson_id'] as int?,
    roomId: j['room_id'] as int?,
    buildingId: j['building_id'] as int?,
    ordinal: j['ordinal'] as int?,
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
