import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../core/util/names.dart';
import '../models/day_schedule.dart';
import '../models/lesson.dart';
import '../models/room_info.dart';
import '../models/schedule_item.dart';
import '../models/student_homework.dart';
import '../models/teacher_profile.dart';
import 'auth_service.dart';

/// Реальное расписание через четыре эндпоинта:
/// - /jersey/api/schedule_items       — уроки (время, предмет, teacher_id, room_id, hw-id);
/// - /core/api/student_homeworks      — тексты ДЗ по homework_id;
/// - /core/api/teacher_profiles       — ФИО учителей по teacher_id;
/// - /core/api/rooms                  — номер кабинета по room_id
///                                       (в schedule_items есть только room_name,
///                                       человеческий номер — только тут).
///
/// group_id приходит снаружи (из /core/api/student_profiles → groups[]),
/// потому что у каждого ученика он свой. Без него schedule_items
/// отвечает 400 "Не найдены группы".
///
/// Все HTTP-запросы идут через ApiClient (единая точка: заголовки,
/// ретраи, проверка сессии) — этот сервис только строит Uri и парсит JSON.
class ScheduleService {
  final ApiClient _api;

  ScheduleService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<DaySchedule>> fetchSchedule(
      EposTokens tokens, {
        required DateTime weekStart,
        required int academicYearId,
        required List<int> groupIds,
      }) async {
    final monday = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final sunday = monday.add(const Duration(days: 6));

    // Расписание и ДЗ — параллельно.
    final results = await Future.wait<Object>([
      _fetchItems(tokens, monday, sunday, academicYearId, groupIds),
      _fetchHomeworks(tokens, monday, sunday, academicYearId),
    ]);
    final items = results[0] as List<ScheduleItem>;
    final homeworks = results[1] as Map<int, String>;

    // Учителя и кабинеты — второй волной, id известны только после первого запроса.
    final teacherIds = items.map((e) => e.teacherId).whereType<int>().toSet();
    final roomIds = items.map((e) => e.roomId).whereType<int>().toSet();
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

    // Собираем уроки по датам в пределах недели.
    final byDate = <String, List<Lesson>>{};
    for (final item in items) {
      if (item.date.isBefore(monday) || item.date.isAfter(sunday)) continue;

      byDate.putIfAbsent(isoDate(item.date), () => []).add(
        Lesson(
          id: item.id,
          startTime: item.beginTime,
          endTime: item.endTime,
          subject: item.subjectName,
          subjectId: item.subjectId,
          homeworks: _homeworkTexts(item.homeworkIds, homeworks),
          teacher: item.teacherId == null ? null : teachers[item.teacherId],
          room: _roomLine(item.roomId, item.roomName, rooms),
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

  /// Тексты ДЗ по всем id урока, в порядке homeworks_to_give.
  /// "не задано" (в любом регистре/написании) и пустые строки не попадают
  /// в список — они и так рисуются в UI как "не задано" при пустом списке.
  List<String> _homeworkTexts(List<int> ids, Map<int, String> map) {
    final result = <String>[];
    for (final id in ids) {
      final text = map[id]?.trim();
      if (text == null || text.isEmpty) continue;
      final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (normalized == 'не задано') continue;
      result.add(text);
    }
    return result;
  }

  /// "Кабинет: 226" по умолчанию, либо "Спортивный зал: 226" /
  /// "Информационный центр (библиотека): 357" и т.п., если у кабинета
  /// осмысленное собственное имя (не общее "Учебный кабинет").
  String? _roomLine(int? roomId, String? roomName, Map<int, RoomInfo> rooms) {
    final info = roomId == null ? null : rooms[roomId];
    final number = info?.number;
    final name = (roomName ?? info?.name)?.trim();
    if (number == null || number.isEmpty) return name;
    final label =
    (name == null || name.isEmpty || name.toLowerCase() == 'учебный кабинет')
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
      ) async {
    // Собираем URL строкой, а не через Uri.https(queryMap): Dart кодирует
    // запятые в group_id как %2C, и сервер на такое отвечает 400.
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/jersey/api/schedule_items'
          '?from=${isoDate(from)}'
          '&to=${isoDate(to)}'
          '&academic_year_id=$academicYearId'
          '&student_profile_id=${tokens.profileId}'
          '&with_group_class_subject_info=true'
          '&with_rooms_info=true'
          '&with_course_calendar_info=true'
          '&with_lesson_info=true'
          '&with_column=true'
          '&cancelled=false'
          '&group_id=${groupIds.join(',')}'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 3);
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ScheduleItem.fromJson)
        .toList();
  }

  /// При ошибке тихо возвращаем пустую карту — расписание отрисуется
  /// без ДЗ, это не повод ронять весь экран.
  Future<Map<int, String>> _fetchHomeworks(
      EposTokens tokens,
      DateTime from,
      DateTime to,
      int academicYearId,
      ) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/student_homeworks'
          '?begin_date=${dotDate(from)}'
          '&end_date=${dotDate(to)}'
          '&academic_year_id=$academicYearId'
          '&student_profile_id=${tokens.profileId}'
          '&page=1'
          '&per_page=1000'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 1, silent: true);
    final map = <int, String>{};
    for (final raw in decoded.whereType<Map<String, dynamic>>()) {
      final hw = StudentHomework.fromJson(raw);
      if (hw.homeworkId > 0) map[hw.homeworkId] = hw.description;
    }
    return map;
  }

  /// Аналогично — если учителя не подтянулись, уроки отрисуются без ФИО.
  Future<Map<int, String>> _fetchTeachers(
      EposTokens tokens,
      Set<int> ids,
      int academicYearId,
      ) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/teacher_profiles'
          '?academic_year_id=$academicYearId'
          '&ids=${ids.join(',')}'
          '&types=all'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 1, silent: true);
    final map = <int, String>{};
    for (final raw in decoded.whereType<Map<String, dynamic>>()) {
      final t = TeacherProfile.fromJson(raw);
      if (t.id > 0) map[t.id] = shortTeacherName(t.name);
    }
    return map;
  }

  /// Аналогично — если номера кабинетов не подтянулись, останется
  /// хотя бы room_name из schedule_items (без номера).
  Future<Map<int, RoomInfo>> _fetchRooms(
      EposTokens tokens,
      Set<int> ids,
      ) async {
    final uri = Uri.parse(
      'https://edu-epos.permkrai.ru/core/api/rooms'
          '?ids=${ids.join(',')}'
          '&all_schools=true'
          '&pid=${tokens.profileId}',
    );
    final decoded = await _api.getList(uri, tokens, attempts: 1, silent: true);
    final map = <int, RoomInfo>{};
    for (final raw in decoded.whereType<Map<String, dynamic>>()) {
      final r = RoomInfo.fromJson(raw);
      if (r.id > 0) map[r.id] = r;
    }
    return map;
  }
}