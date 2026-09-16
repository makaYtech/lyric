/// Ответ /core/api/bells_timetables — расписание звонков.
/// Сервер возвращает массив, обычно из одного элемента (наша школа).
/// Парсер работает с ОДНИМ элементом; обёртку над массивом делает сервис.
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

/// Один звонок. isLesson == false — перемена. Уроки имеют study_ordinal
/// (номер урока по порядку, 1..N); перемены его не имеют.
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

/// Удобные запросы к расписанию звонков. Используем в gap_utils и в
/// диалоге выбора слота при drop на окно.
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
      ..sort((a, b) =>
          (a.studyOrdinal ?? 0).compareTo(b.studyOrdinal ?? 0));
    return out;
  }

  /// Время начала первого урока дня.
  String? firstLessonStart(int weekDayId) {
    final slots = lessonSlots(weekDayId);
    if (slots.isEmpty) return null;
    return slots.first.beginTime;
  }

  /// Слот, время начала которого совпадает с [startTime] ("HH:mm").
  /// Используется, чтобы по уроку из schedule_items понять, какой это
  /// слот звонков: 08:30 → слот 1, 09:25 → слот 2.
  Bell? slotByStartTime(int weekDayId, String startTime) {
    final day = dayFor(weekDayId);
    if (day == null) return null;
    for (final b in day.bells) {
      if (b.isLesson && b.beginTime == startTime) return b;
    }
    return null;
  }

  /// Слоты, которые ЦЕЛИКОМ попадают в интервал [from..to] (границы
  /// включительно). Используется при drop на окно: юзеру показываем
  /// варианты «сюда можно поставить урок».
  ///
  /// Учитываем только те слоты, чей интервал [begin_time..end_time]
  /// не выходит за границы окна.
  List<Bell> slotsInsideInterval(int weekDayId, String from, String to) {
    final slots = lessonSlots(weekDayId);
    final fromM = _toMin(from);
    final toM = _toMin(to);
    if (fromM == null || toM == null) return const [];
    final out = <Bell>[];
    for (final b in slots) {
      final bM = _toMin(b.beginTime);
      final eM = _toMin(b.endTime);
      if (bM == null || eM == null) continue;
      if (bM >= fromM && eM <= toM) out.add(b);
    }
    return out;
  }

  static int? _toMin(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}