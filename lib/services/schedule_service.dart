import '../core/network/api_client.dart';
import '../core/util/date_time.dart';
import '../core/util/names.dart';
import '../models/day_schedule.dart';
import '../models/ec_homework.dart';
import '../models/ec_schedule_item.dart';
import '../models/homework_attachment.dart';
import '../models/lesson.dart';
import '../models/room_info.dart';
import '../models/schedule_item.dart';
import '../models/student_homework.dart';
import '../models/teacher_profile.dart';
import 'auth_service.dart';
import 'ec_homework_service.dart';
import 'ec_schedule_service.dart';

/// Реальное расписание через шесть эндпоинтов:
/// - /jersey/api/schedule_items     — обычные уроки (время, предмет,
///                                    teacher_id, room_id, hw-id);
/// - /core/api/student_homeworks    — тексты ДЗ по homework_id;
/// - /core/api/teacher_profiles     — ФИО учителей по teacher_id;
/// - /core/api/rooms                — номер кабинета по room_id
///                                    (в schedule_items есть только room_name,
///                                    человеческий номер — только тут);
/// - /ec/api/ec_schedule_items      — внеурочные занятия;
/// - /ec/api/ec_student_homeworks   — тексты ДЗ внеурочки.
///
/// group_id приходит снаружи (из /core/api/student_profiles → groups[]),
/// потому что у каждого ученика он свой. Без него schedule_items
/// отвечает 400 "Не найдены группы".
///
/// ec_group_ids тоже приходит снаружи — он собирается контроллером
/// из ответа ec_student_homeworks (там он есть в каждой записи),
/// потому что в student_profiles его нет.
///
/// Все HTTP-запросы идут через ApiClient (единая точка: заголовки,
/// ретраи, проверка сессии) — этот сервис только строит Uri и парсит JSON.
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
  }) async {
    final monday = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final sunday = monday.add(const Duration(days: 6));

    // Первая волна — четыре запроса параллельно.
    final results = await Future.wait<Object>([
      _fetchItems(tokens, monday, sunday, academicYearId, groupIds),
      _fetchHomeworks(tokens, monday, sunday, academicYearId),
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
    final homeworks = results[1] as Map<int, StudentHomework>;
    final ecItems = results[2] as List<EcScheduleItem>;
    final ecHomeworks = results[3] as List<EcHomework>;

    // Учителя и кабинеты — второй волной, id известны только после
    // первого запроса. id-шники собираем и из обычных, и из EC.
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

    // ── Названия EC-активностей ─────────────────────────────────────────
    //
    // В /ec/api/ec_schedule_items приходит только ec_activity_id и
    // ec_course_calendar_lesson_name (это ТЕМА конкретного занятия,
    // например "Илья Муромец"). А название предмета ("Разговоры
    // о важном", "Россия — мои горизонты") лежит в
    // ec_activity.name внутри ответа ec_student_homeworks.
    //
    // Поэтому строим мапу id → name из только что загруженных EC-ДЗ.
    // Если на конкретном уроке из этой недели ДЗ не оказалось —
    // подставим тему как fallback (лучше, чем ничего).
    final ecActivityNames = <int, String>{};
    for (final h in ecHomeworks) {
      final id = h.ecActivityId;
      final name = h.activityName;
      if (id != null && name != null && name.isNotEmpty) {
        ecActivityNames[id] = name;
      }
    }

    // EC-ДЗ по homework_id — чтобы матчить к EC-урокам по их id.
    final ecHwByHomeworkId = <int, EcHomework>{};
    for (final h in ecHomeworks) {
      if (h.homeworkId > 0) ecHwByHomeworkId[h.homeworkId] = h;
    }

    // Собираем уроки по датам в пределах недели.
    final byDate = <String, List<Lesson>>{};

    for (final item in items) {
      if (item.date.isBefore(monday) || item.date.isAfter(sunday)) continue;

      byDate
          .putIfAbsent(isoDate(item.date), () => [])
          .add(
            Lesson(
              id: item.id,
              startTime: item.beginTime,
              endTime: item.endTime,
              subject: item.subjectName,
              subjectId: item.subjectId,
              homeworks: _homeworkTexts(item.homeworkIds, homeworks),
              studentHomeworkIds: _studentHomeworkIds(
                item.homeworkIds,
                homeworks,
              ),
              attachments: _homeworkAttachments(item.homeworkIds, homeworks),
              teacher: item.teacherId == null ? null : teachers[item.teacherId],
              teacherId: item.teacherId,
              room: _roomLine(item.roomId, item.roomName, rooms),
            ),
          );
    }

    for (final ec in ecItems) {
      if (ec.date.isBefore(monday) || ec.date.isAfter(sunday)) continue;

      // Название ПРЕДМЕТА: сначала activity.name ("Разговоры о важном"),
      // если её знаем по id. Иначе — то, что пришло в ec_schedule_items
      // (ec_course_calendar_lesson_name, это тема занятия).
      final subject = ecActivityNames[ec.ecActivityId] ?? ec.name;

      // На EC-уроке показываем и то, что задали (homeworks_to_give),
      // и то, что надо сдать (homeworks_to_verify). На обычных уроках
      // verify игнорируется, но у внеурочки ДЗ часто висит именно там.
      final allHwIds = <int>{
        ...ec.homeworksToGive,
        ...ec.homeworksToVerify,
      }.toList();

      final hwTexts = <String>[];
      for (final hwId in allHwIds) {
        final h = ecHwByHomeworkId[hwId];
        if (h == null) continue;
        if (!_isMeaningfulText(h.description)) continue;
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
              // «Моя работа» для EC пока не поддержана — id'шники пустые,
              // чтобы UI не дёргал /core/api/student_homeworks/{ecId}.
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

  /// Проверка «есть ли в тексте что-то, кроме «не задано»». Работает
  /// по строке — общая для обычных StudentHomework и EC-ДЗ.
  bool _isMeaningfulText(String? raw) {
    if (raw == null) return false;
    final text = raw.trim();
    if (text.isEmpty) return false;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized != 'не задано';
  }

  bool _isMeaningful(StudentHomework? hw) => _isMeaningfulText(hw?.description);

  /// Тексты ДЗ по всем id урока, в порядке homeworks_to_give.
  List<String> _homeworkTexts(List<int> ids, Map<int, StudentHomework> map) {
    final result = <String>[];
    for (final id in ids) {
      final hw = map[id];
      if (!_isMeaningful(hw)) continue;
      result.add(hw!.description.trim());
    }
    return result;
  }

  /// id записей student_homework — строго параллельно _homeworkTexts.
  List<int> _studentHomeworkIds(List<int> ids, Map<int, StudentHomework> map) {
    final result = <int>[];
    for (final id in ids) {
      final hw = map[id];
      if (!_isMeaningful(hw)) continue;
      result.add(hw!.id);
    }
    return result;
  }

  /// Собираем вложения со всех ДЗ урока, дедуп по url. Если у одного
  /// урока три ДЗ и в каждом — свой pdf, в модалке будет три кнопки.
  List<HomeworkAttachment> _homeworkAttachments(
    List<int> ids,
    Map<int, StudentHomework> map,
  ) {
    final seen = <String>{};
    final result = <HomeworkAttachment>[];
    for (final id in ids) {
      final hw = map[id];
      if (hw == null) continue;
      for (final a in hw.attachments) {
        if (seen.add(a.url)) result.add(a);
      }
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
  Future<Map<int, StudentHomework>> _fetchHomeworks(
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
    final map = <int, StudentHomework>{};
    for (final raw in decoded.whereType<Map<String, dynamic>>()) {
      final hw = StudentHomework.fromJson(raw);
      if (hw.homeworkId > 0) map[hw.homeworkId] = hw;
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
