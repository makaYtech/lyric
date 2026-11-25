import '../../core/util/date_time.dart';
import '../../core/util/json.dart';

/// Ответ /core/api/bells_timetables — расписание звонков.
/// Сервер отдаёт массив; парсер работает с одним элементом, обёртку
/// над массивом делает сервис.
class BellsTimetable {
  final int id;
  final List<BellsDay> days;

  const BellsTimetable({required this.id, required this.days});

  factory BellsTimetable.fromJson(Map<String, dynamic> json) {
    return BellsTimetable(
      id: json.intOr('id', 0),
      days: json
          .mapList('bells_day_timetables')
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
    return BellsDay(
      weekDayId: json.intOr('week_day_id', 0),
      bells: json.mapList('bells').map(Bell.fromJson).toList(),
    );
  }
}

/// Один звонок. isLesson == false — перемена; studyOrdinal есть только
/// у уроков (номер по порядку, 1..N).
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
    studyOrdinal: json.intOrNull('study_ordinal'),
    isLesson: json.boolOr('is_lesson'),
    beginTime: json.str('begin_time'),
    endTime: json.str('end_time'),
  );
}

/// Запросы к расписанию звонков для gap_utils и диалога выбора слота.
extension BellsTimetableLookup on BellsTimetable {
  BellsDay? dayFor(int weekDayId) {
    for (final d in days) {
      if (d.weekDayId == weekDayId) return d;
    }
    return null;
  }

  /// Слот по номеру урока (study_ordinal).
  Bell? slotFor(int weekDayId, int studyOrdinal) {
    final day = dayFor(weekDayId);
    if (day == null) return null;
    for (final b in day.bells) {
      if (b.isLesson && b.studyOrdinal == studyOrdinal) return b;
    }
    return null;
  }

  /// Все уроки дня в порядке study_ordinal.
  List<Bell> lessonSlots(int weekDayId) {
    final day = dayFor(weekDayId);
    if (day == null) return const [];
    final out = day.bells.where((b) => b.isLesson).toList()
      ..sort((a, b) => (a.studyOrdinal ?? 0).compareTo(b.studyOrdinal ?? 0));
    return out;
  }

  /// Время начала первого урока дня.
  String? firstLessonStart(int weekDayId) {
    final slots = lessonSlots(weekDayId);
    if (slots.isEmpty) return null;
    return slots.first.beginTime;
  }

  /// Слот, начинающийся в [startTime] ("HH:mm"): 08:30 → слот 1.
  Bell? slotByStartTime(int weekDayId, String startTime) {
    final day = dayFor(weekDayId);
    if (day == null) return null;
    for (final b in day.bells) {
      if (b.isLesson && b.beginTime == startTime) return b;
    }
    return null;
  }

  /// Слоты, целиком попадающие в [from..to] (границы включительно) —
  /// варианты для drop на окно.
  List<Bell> slotsInsideInterval(int weekDayId, String from, String to) {
    final slots = lessonSlots(weekDayId);
    final fromM = minutesFromHhmm(from);
    final toM = minutesFromHhmm(to);
    if (fromM == null || toM == null) return const [];
    final out = <Bell>[];
    for (final b in slots) {
      final bM = minutesFromHhmm(b.beginTime);
      final eM = minutesFromHhmm(b.endTime);
      if (bM == null || eM == null) continue;
      if (bM >= fromM && eM <= toM) out.add(b);
    }
    return out;
  }
}
