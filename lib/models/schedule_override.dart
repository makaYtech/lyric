import 'dart:convert';

import '../core/util/date_time.dart';
import 'day_schedule.dart';
import 'lesson.dart';

enum ScheduleOverrideKind { delete, move, pairBreak, pairMake, reorder }

class ScheduleOverride {
  final int? id;
  final int yearId;
  final DateTime date;
  final ScheduleOverrideKind kind;
  final int primaryLessonId;
  final int? secondaryLessonId;
  final String? payload;
  final DateTime createdAt;

  const ScheduleOverride({
    this.id,
    required this.yearId,
    required this.date,
    required this.kind,
    required this.primaryLessonId,
    this.secondaryLessonId,
    this.payload,
    required this.createdAt,
  });

  factory ScheduleOverride.delete({
    required int yearId,
    required DateTime date,
    required int lessonId,
  }) => ScheduleOverride(
    yearId: yearId,
    date: dayOnly(date),
    kind: ScheduleOverrideKind.delete,
    primaryLessonId: lessonId,
    createdAt: DateTime.now(),
  );

  factory ScheduleOverride.move({
    required int yearId,
    required DateTime date,
    required int lessonId,
    required String startTime,
    required String endTime,
  }) => ScheduleOverride(
    yearId: yearId,
    date: dayOnly(date),
    kind: ScheduleOverrideKind.move,
    primaryLessonId: lessonId,
    payload: jsonEncode({'start_time': startTime, 'end_time': endTime}),
    createdAt: DateTime.now(),
  );

  factory ScheduleOverride.pairBreak({
    required int yearId,
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) => ScheduleOverride(
    yearId: yearId,
    date: dayOnly(date),
    kind: ScheduleOverrideKind.pairBreak,
    primaryLessonId: primaryId,
    secondaryLessonId: secondaryId,
    createdAt: DateTime.now(),
  );

  factory ScheduleOverride.pairMake({
    required int yearId,
    required DateTime date,
    required int primaryId,
    required int secondaryId,
  }) => ScheduleOverride(
    yearId: yearId,
    date: dayOnly(date),
    kind: ScheduleOverrideKind.pairMake,
    primaryLessonId: primaryId,
    secondaryLessonId: secondaryId,
    createdAt: DateTime.now(),
  );

  factory ScheduleOverride.reorder({
    required int yearId,
    required DateTime date,
    required List<int> order,
  }) => ScheduleOverride(
    yearId: yearId,
    date: dayOnly(date),
    kind: ScheduleOverrideKind.reorder,
    primaryLessonId: order.isEmpty ? 0 : order.first,
    payload: jsonEncode({'order': order}),
    createdAt: DateTime.now(),
  );

  Map<String, dynamic> toRow() => {
    if (id != null) 'id': id,
    'year_id': yearId,
    'date': isoDate(date),
    'kind': kind.name,
    'primary_lesson_id': primaryLessonId,
    'secondary_lesson_id': secondaryLessonId,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
  };

  factory ScheduleOverride.fromRow(Map<String, dynamic> r) => ScheduleOverride(
    id: r['id'] as int?,
    yearId: r['year_id'] as int,
    date: DateTime.parse(r['date'] as String),
    kind: ScheduleOverrideKind.values.byName(r['kind'] as String),
    primaryLessonId: r['primary_lesson_id'] as int,
    secondaryLessonId: r['secondary_lesson_id'] as int?,
    payload: r['payload'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  List<int> reorderOrder() {
    if (kind != ScheduleOverrideKind.reorder) return const [];
    final p = payload;
    if (p == null) return const [];
    try {
      final m = jsonDecode(p) as Map<String, dynamic>;
      final raw = m['order'];
      if (raw is! List) return const [];
      return raw.whereType<num>().map((e) => e.toInt()).toList();
    } catch (_) {
      return const [];
    }
  }
}

List<DaySchedule> applyScheduleOverrides(
  List<DaySchedule> days,
  List<ScheduleOverride> overrides,
) {
  if (overrides.isEmpty) return days;

  final byDate = <String, List<ScheduleOverride>>{};
  for (final o in overrides) {
    byDate.putIfAbsent(isoDate(o.date), () => []).add(o);
  }

  return days.map((day) {
    final ovr = byDate[isoDate(day.date)];
    if (ovr == null || ovr.isEmpty) return day;
    return _applyDay(day, ovr);
  }).toList();
}

DaySchedule _applyDay(DaySchedule day, List<ScheduleOverride> ovr) {
  final deleted = <int>{};
  final moves = <int, ({String start, String end})>{};
  final forceBreaks = <int>{};
  final forceMakes = <int, int>{}; // primary → secondary
  ScheduleOverride? reorder;

  for (final o in ovr) {
    switch (o.kind) {
      case ScheduleOverrideKind.delete:
        deleted.add(o.primaryLessonId);
      case ScheduleOverrideKind.move:
        final p = o.payload;
        if (p == null) break;
        try {
          final m = jsonDecode(p) as Map<String, dynamic>;
          final s = m['start_time'] as String?;
          final e = m['end_time'] as String?;
          if (s != null && e != null) {
            moves[o.primaryLessonId] = (start: s, end: e);
          }
        } catch (_) {}
      case ScheduleOverrideKind.pairBreak:
        forceBreaks.add(o.primaryLessonId);
      case ScheduleOverrideKind.pairMake:
        final s = o.secondaryLessonId;
        if (s != null) forceMakes[o.primaryLessonId] = s;
      case ScheduleOverrideKind.reorder:
        reorder = o;
    }
  }

  final lessons = <Lesson>[];
  for (final l in day.lessons) {
    final id = l.id;
    if (id == null) {
      lessons.add(l);
      continue;
    }
    if (deleted.contains(id)) continue;
    final m = moves[id];
    if (m == null) {
      lessons.add(l);
    } else {
      lessons.add(l.copyWith(startTime: m.start, endTime: m.end));
    }
  }

  List<Lesson> sorted;
  if (reorder != null) {
    final order = reorder.reorderOrder();
    final sortedByTime = [...lessons]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final slots = sortedByTime
        .map((l) => (start: l.startTime, end: l.endTime))
        .toList();

    final byId = <int, Lesson>{};
    for (final l in lessons) {
      if (l.id != null) byId[l.id!] = l;
    }

    final result = <Lesson>[];
    final placed = <int>{};
    for (var i = 0; i < order.length && i < slots.length; i++) {
      final l = byId[order[i]];
      if (l == null) continue;
      placed.add(order[i]);
      result.add(l.copyWith(startTime: slots[i].start, endTime: slots[i].end));
    }
    for (final l in lessons) {
      if (l.id != null && placed.contains(l.id)) continue;
      result.add(l);
    }
    sorted = result;
  } else {
    sorted = [...lessons]..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // Пары: forceBreak снимает авто-слияние, forceMake — принудительно
  // ставит маркер breakWithNext на SECONDARY, чтобы mergeLessonPairs
  // не слил того со следующим, а на PRIMARY — маркер для merge.
  //
  // Проще: forceMake — помечаем primary так, чтобы mergeLessonPairs
  // его НЕ пропускал по break-логике. Для этого достаточно НЕ помечать
  // primary. А secondary надо защитить от слияния со следующим через
  // pairOverride на нём (если бы он там был). Отдельный break на
  // secondary в нашем mergeLessonPairs не поддерживается — там работает
  // только breakWithNext на ПЕРВОМ уроке. Так что пара из forceMake
  // просто работает через _sameSlot, если предмет/учитель/кабинет
  // совпадают. Если не совпадают — она не склеится.
  //
  // Это ограничение приемлемо: forceMake из разных предметов мы и
  // запрещаем на уровне UI (_canMakePair).

  final marked = <Lesson>[];
  for (final l in sorted) {
    final id = l.id;
    final fb = id == null ? false : forceBreaks.contains(id);
    marked.add(
      Lesson(
        id: l.id,
        secondaryId: l.secondaryId,
        startTime: l.startTime,
        endTime: l.endTime,
        subject: l.subject,
        subjectId: l.subjectId,
        homeworks: l.homeworks,
        attachments: l.attachments,
        teacher: l.teacher,
        teacherId: l.teacherId,
        room: l.room,
        isPaired: l.isPaired,
        breakMinutes: l.breakMinutes,
        studentHomeworkIds: l.studentHomeworkIds,
        pairOverride: fb ? LessonPairOverride.breakWithNext : null,
      ),
    );
  }

  return DaySchedule(date: day.date, lessons: marked);
}
