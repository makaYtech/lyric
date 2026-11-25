import 'dart:convert';

import '../../core/util/date_time.dart';
import '../../core/util/json.dart';
import '../homework/homework_attachment.dart';

enum LessonPairOverride { breakWithNext }

class Lesson {
  final int? id;
  final int? secondaryId;
  final String startTime;
  final String endTime;
  final String subject;
  final int? subjectId;
  final List<String> homeworks;

  /// id ДЗ (homework.id) из homeworks_to_give — сырые, из них при
  /// пересборке из кэша восстанавливается блок «ДЗ».
  final List<int> homeworkIds;

  /// id записей student_homework — уходят в PUT при прикреплении
  /// своего файла («Моя работа»).
  final List<int> studentHomeworkIds;

  final List<HomeworkAttachment> attachments;
  final String? teacher;
  final int? teacherId;
  final String? room;
  final bool isPaired;
  final int? breakMinutes;
  final LessonPairOverride? pairOverride;

  /// Синтетический урок-окно (разрыв между уроками): отрицательный id,
  /// пустые поля кроме времени. В БД не сохраняется.
  final bool isGap;

  /// Внеурочное занятие из /ec/api/ec_schedule_items.
  final bool isEc;

  const Lesson({
    this.id,
    this.secondaryId,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.subjectId,
    this.homeworks = const [],
    this.homeworkIds = const [],
    this.attachments = const [],
    this.teacher,
    this.teacherId,
    this.room,
    this.isPaired = false,
    this.breakMinutes,
    this.studentHomeworkIds = const [],
    this.pairOverride,
    this.isGap = false,
    this.isEc = false,
  });

  /// Длительность в минутах; для окна — длина разрыва.
  int? get durationMinutes {
    final s = minutesFromHhmm(startTime);
    final e = minutesFromHhmm(endTime);
    if (s == null || e == null) return null;
    return e - s;
  }

  Lesson copyWith({
    int? id,
    int? secondaryId,
    String? startTime,
    String? endTime,
    String? subject,
    int? subjectId,
    List<String>? homeworks,
    List<int>? homeworkIds,
    List<HomeworkAttachment>? attachments,
    String? teacher,
    int? teacherId,
    String? room,
    bool? isPaired,
    int? breakMinutes,
    List<int>? studentHomeworkIds,
    LessonPairOverride? pairOverride,
    bool? isGap,
    bool? isEc,
  }) => Lesson(
    id: id ?? this.id,
    secondaryId: secondaryId ?? this.secondaryId,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    subject: subject ?? this.subject,
    subjectId: subjectId ?? this.subjectId,
    homeworks: homeworks ?? this.homeworks,
    homeworkIds: homeworkIds ?? this.homeworkIds,
    attachments: attachments ?? this.attachments,
    teacher: teacher ?? this.teacher,
    teacherId: teacherId ?? this.teacherId,
    room: room ?? this.room,
    isPaired: isPaired ?? this.isPaired,
    breakMinutes: breakMinutes ?? this.breakMinutes,
    studentHomeworkIds: studentHomeworkIds ?? this.studentHomeworkIds,
    pairOverride: pairOverride ?? this.pairOverride,
    isGap: isGap ?? this.isGap,
    isEc: isEc ?? this.isEc,
  );

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    id: json.intOrNull('id'),
    startTime: json.str('start_time'),
    endTime: json.str('end_time'),
    subject: json.strOr('subject', '—'),
    subjectId: json.intOrNull('subject_id'),
    homeworks: decodeHomeworks(json['homework']),
    homeworkIds: _decodeIds(json['homework_ids']),
    attachments: HomeworkAttachment.listFromJson(json['attachments']),
    teacher: json['teacher'] as String?,
    teacherId: json.intOrNull('teacher_id'),
    room: json['room'] as String?,
    studentHomeworkIds: _decodeIds(json['student_homework_ids']),
    isEc: json.boolOr('is_ec'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start_time': startTime,
    'end_time': endTime,
    'subject': subject,
    'subject_id': subjectId,
    'homework': jsonEncode(homeworks),
    'homework_ids': homeworkIds,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'teacher': teacher,
    'teacher_id': teacherId,
    'room': room,
    'student_homework_ids': studentHomeworkIds,
    'is_ec': isEc,
  };

  static List<String> decodeHomeworks(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.whereType<String>().toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {}
      return [raw];
    }
    return const [];
  }

  String get homeworkDisplay =>
      homeworks.isEmpty ? 'не задано' : homeworks.first;

  static List<int> _decodeIds(Object? raw) {
    if (raw is List) return raw.whereType<num>().map((e) => e.toInt()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) return d.whereType<num>().map((e) => e.toInt()).toList();
      } catch (_) {}
    }
    return const [];
  }
}

List<Lesson> mergeLessonPairs(List<Lesson> lessons) {
  final result = <Lesson>[];
  var i = 0;
  while (i < lessons.length) {
    final a = lessons[i];
    if (a.pairOverride == LessonPairOverride.breakWithNext || a.isGap) {
      result.add(a);
      i += 1;
      continue;
    }
    if (i + 1 < lessons.length) {
      final b = lessons[i + 1];
      if (b.pairOverride != LessonPairOverride.breakWithNext &&
          !b.isGap &&
          _sameSlot(a, b)) {
        result.add(_mergeTwo(a, b));
        i += 2;
        continue;
      }
    }
    result.add(a);
    i += 1;
  }
  return result;
}

Lesson _mergeTwo(Lesson a, Lesson b) {
  final homeworks = <String>[...a.homeworks, ...b.homeworks];
  final startMin = minutesFromHhmm(a.endTime);
  final endMin = minutesFromHhmm(b.startTime);

  final seen = <String>{};
  final attachments = <HomeworkAttachment>[];
  for (final att in [...a.attachments, ...b.attachments]) {
    if (seen.add(att.url)) attachments.add(att);
  }

  final seenHw = <int>{};
  final homeworkIds = <int>[];
  for (final id in [...a.homeworkIds, ...b.homeworkIds]) {
    if (seenHw.add(id)) homeworkIds.add(id);
  }

  return Lesson(
    id: a.id,
    secondaryId: b.id,
    startTime: a.startTime,
    endTime: b.endTime,
    subject: a.subject,
    subjectId: a.subjectId,
    homeworks: homeworks,
    homeworkIds: homeworkIds,
    attachments: attachments,
    teacher: a.teacher,
    teacherId: a.teacherId,
    room: a.room,
    isPaired: true,
    breakMinutes: (startMin != null && endMin != null)
        ? endMin - startMin
        : null,
    studentHomeworkIds: [...a.studentHomeworkIds, ...b.studentHomeworkIds],
    isEc: a.isEc,
  );
}

bool _sameSlot(Lesson a, Lesson b) =>
    a.subject == b.subject && a.teacher == b.teacher && a.room == b.room;
