import '../../../core/network/api_client.dart';
import '../../../core/schedule/homework_matching.dart';
import '../../../core/util/date_time.dart';
import '../../../core/util/names.dart';
import '../../../domain/schedule/day_schedule.dart';
import '../../../domain/homework/ec_homework.dart';
import '../../../domain/schedule/ec_schedule_item.dart';
import '../../../domain/homework/homework.dart';
import '../../../domain/schedule/lesson.dart';
import '../../../domain/common/room_info.dart';
import '../../../domain/schedule/schedule_item.dart';
import '../../../domain/people/teacher_profile.dart';
import './api_endpoints.dart';
import './auth_service.dart';
import './ec_homework_service.dart';
import './ec_schedule_service.dart';

/// Реальное расписание через пять эндпоинтов: schedule_items,
/// teacher_profiles, rooms, ec_schedule_items и ec_student_homeworks.
///
/// group_id приходит снаружи (из student_profiles → groups[]): без него
/// schedule_items отвечает 400 «Не найдены группы». ec_group_ids тоже
/// снаружи — их собирает контроллер из ec_student_homeworks.
///
/// ДЗ из student_homeworks тянет не этот сервис, а HomeController:
/// ему нужен годовой список для БД и офлайн-пересборки. Сюда он
/// приходит готовым через allHomeworks.
class ScheduleService {
  final ApiClient _api;
  final EcScheduleService _ecSchedule;
  final EcHomeworkService _ecHomeworks;

  ScheduleService({
    ApiClient? api,
    EcScheduleService? ecSchedule,
    EcHomeworkService? ecHomeworks,
  }) : _api = api ?? ApiClient(),
       _ecSchedule = ecSchedule ?? EcScheduleService(),
       _ecHomeworks = ecHomeworks ?? EcHomeworkService();

  Future<List<DaySchedule>> fetchSchedule(
    EposTokens tokens, {
    required DateTime weekStart,
    required int academicYearId,
    required List<int> groupIds,
    List<int> ecGroupIds = const [],
    List<int> classUnitIds = const [],
    bool groupHomeworksByDue = false,
    required List<Homework> allHomeworks,
  }) async {
    final monday = dayOnly(weekStart);
    final sunday = monday.add(const Duration(days: 6));

    // Та же логика матчинга, что при пересборке из кэша.
    final maps = HomeworkMatching.buildMaps(allHomeworks);

    final results = await Future.wait<Object>([
      _fetchItems(tokens, monday, sunday, academicYearId, groupIds),
      _ecSchedule.fetchEcItems(
        tokens,
        from: monday,
        to: sunday,
        academicYearId: academicYearId,
        ecGroupIds: ecGroupIds,
        classUnitIds: classUnitIds,
      ),
      _ecHomeworks.fetchEcHomeworks(
        tokens,
        from: monday,
        to: sunday,
        academicYearId: academicYearId,
      ),
    ]);
    final items = results[0] as List<ScheduleItem>;
    final ecItems = results[1] as List<EcScheduleItem>;
    final ecHomeworks = results[2] as List<EcHomework>;

    // Учителя и кабинеты — второй волной: id известны только после
    // первого запроса.
    final teacherIds = <int>{
      for (final e in items)
        if (e.teacherId != null) e.teacherId!,
      for (final e in ecItems)
        if (e.teacherId != null) e.teacherId!,
    };
    final roomIds = <int>{
      for (final e in items)
        if (e.roomId != null) e.roomId!,
      for (final e in ecItems)
        if (e.roomId != null) e.roomId!,
    };
    final secondWave = await Future.wait<Object>([
      teacherIds.isEmpty
          ? Future.value(const <int, String>{})
          : _fetchTeachers(tokens, teacherIds, academicYearId),
      roomIds.isEmpty
          ? Future.value(const <int, RoomInfo>{})
          : _fetchRooms(tokens, roomIds),
    ]);
    final teachers = secondWave[0] as Map<int, String>;
    final rooms = secondWave[1] as Map<int, RoomInfo>;

    // В ec_schedule_items приходит только тема занятия
    // (ec_course_calendar_lesson_name), а название предмета лежит
    // в ec_activity.name внутри ec_student_homeworks.
    final ecActivityNames = <int, String>{};
    for (final h in ecHomeworks) {
      final id = h.ecActivityId;
      final name = h.activityName;
      if (id != null && name != null && name.isNotEmpty) {
        ecActivityNames[id] = name;
      }
    }

    final ecHwByHomeworkId = <int, EcHomework>{};
    for (final h in ecHomeworks) {
      if (h.homeworkId > 0) ecHwByHomeworkId[h.homeworkId] = h;
    }

    final byDate = <String, List<Lesson>>{};

    for (final item in items) {
      if (item.date.isBefore(monday) || item.date.isAfter(sunday)) continue;

      final hw = HomeworkMatching.forLesson(
        subjectId: item.subjectId,
        date: item.date,
        sourceHomeworkIds: item.homeworkIds,
        byId: maps.byId,
        byDue: maps.byDue,
        groupByDue: groupHomeworksByDue,
      );

      byDate
          .putIfAbsent(isoDate(item.date), () => [])
          .add(
            Lesson(
              id: item.id,
              startTime: item.beginTime,
              endTime: item.endTime,
              subject: item.subjectName,
              subjectId: item.subjectId,
              homeworks: hw.texts,
              homeworkIds: item.homeworkIds,
              studentHomeworkIds: hw.ids,
              attachments: hw.attachments,
              teacher: item.teacherId == null ? null : teachers[item.teacherId],
              teacherId: item.teacherId,
              room: _roomLine(item.roomId, item.roomName, rooms),
            ),
          );
    }

    for (final ec in ecItems) {
      if (ec.date.isBefore(monday) || ec.date.isAfter(sunday)) continue;

      // Название предмета: activity.name, если знаем по id, иначе то,
      // что пришло в ec_schedule_items (это тема занятия).
      final subject = ecActivityNames[ec.ecActivityId] ?? ec.name;

      // У внеурочки ДЗ часто висит в homeworks_to_verify, поэтому берём
      // и give, и verify.
      final allHwIds = <int>{
        ...ec.homeworksToGive,
        ...ec.homeworksToVerify,
      }.toList();

      final hwTexts = <String>[];
      for (final hwId in allHwIds) {
        final h = ecHwByHomeworkId[hwId];
        if (h == null) continue;
        if (!HomeworkMatching.isMeaningful(h.description)) continue;
        hwTexts.add(h.description.trim());
      }

      byDate
          .putIfAbsent(isoDate(ec.date), () => [])
          .add(
            Lesson(
              id: ec.id,
              startTime: ec.beginTime,
              endTime: ec.endTime,
              subject: subject,
              homeworks: hwTexts,
              // «Моя работа» для EC не поддержана — пусто, чтобы UI
              // не дёргал /core/api/student_homeworks/{ecId}.
              studentHomeworkIds: const [],
              teacher: ec.teacherId == null ? null : teachers[ec.teacherId],
              teacherId: ec.teacherId,
              room: _roomLine(ec.roomId, null, rooms),
              isEc: true,
            ),
          );
    }

    // Достраиваем Пн–Сб: пустые дни тоже показываем.
    return List.generate(6, (i) {
      final day = monday.add(Duration(days: i));
      final lessons = byDate[isoDate(day)] ?? <Lesson>[];
      lessons.sort((a, b) => a.startTime.compareTo(b.startTime));
      return DaySchedule(date: day, lessons: lessons);
    });
  }

  /// "Кабинет: 226" либо "Спортивный зал: 226", если у кабинета есть
  /// осмысленное имя (не общее "Учебный кабинет").
  String? _roomLine(int? roomId, String? roomName, Map<int, RoomInfo> rooms) {
    final info = roomId == null ? null : rooms[roomId];
    final number = info?.number;
    final name = (roomName ?? info?.name)?.trim();
    if (number == null || number.isEmpty) return name;
    final label =
        (name == null ||
            name.isEmpty ||
            name.toLowerCase() == 'учебный кабинет')
        ? 'Кабинет'
        : name;
    return '$label: $number';
  }

  Future<List<ScheduleItem>> _fetchItems(
    EposTokens tokens,
    DateTime from,
    DateTime to,
    int academicYearId,
    List<int> groupIds,
  ) => _api.getTyped(
    eposUri('/jersey/api/schedule_items', {
      'from': isoDate(from),
      'to': isoDate(to),
      'academic_year_id': academicYearId,
      'student_profile_id': tokens.profileId,
      'with_group_class_subject_info': true,
      'with_rooms_info': true,
      'with_course_calendar_info': true,
      'with_lesson_info': true,
      'with_column': true,
      'cancelled': false,
      'group_id': groupIds.join(','),
      'pid': tokens.profileId,
    }),
    tokens,
    attempts: 3,
    parse: ScheduleItem.fromJson,
  );

  /// Если учителя не подтянулись — уроки отрисуются без ФИО.
  Future<Map<int, String>> _fetchTeachers(
    EposTokens tokens,
    Set<int> ids,
    int academicYearId,
  ) async {
    final profiles = await _api.getTyped(
      eposUri('/core/api/teacher_profiles', {
        'academic_year_id': academicYearId,
        'ids': ids.join(','),
        'types': 'all',
        'pid': tokens.profileId,
      }),
      tokens,
      attempts: 1,
      silent: true,
      parse: TeacherProfile.fromJson,
    );
    final map = <int, String>{};
    for (final t in profiles) {
      if (t.id > 0) map[t.id] = shortTeacherName(t.name);
    }
    return map;
  }

  /// Если номера кабинетов не подтянулись — останется room_name из
  /// schedule_items (без номера).
  Future<Map<int, RoomInfo>> _fetchRooms(
    EposTokens tokens,
    Set<int> ids,
  ) async {
    final list = await _api.getTyped(
      eposUri('/core/api/rooms', {
        'ids': ids.join(','),
        'all_schools': true,
        'pid': tokens.profileId,
      }),
      tokens,
      attempts: 1,
      silent: true,
      parse: RoomInfo.fromJson,
    );
    final map = <int, RoomInfo>{};
    for (final r in list) {
      if (r.id > 0) map[r.id] = r;
    }
    return map;
  }
}
