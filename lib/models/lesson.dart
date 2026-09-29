import 'dart:convert';

import 'homework_attachment.dart';

enum LessonPairOverride { breakWithNext }

class Lesson {
  final int? id;
  final int? secondaryId;
  final String startTime;
  final String endTime;
  final String subject;
  final int? subjectId;
  final List<String> homeworks;
  final List<int> studentHomeworkIds;
  final List<HomeworkAttachment> attachments;
  final String? teacher;
  final int? teacherId;
  final String? room;
  final bool isPaired;
  final int? breakMinutes;
  final LessonPairOverride? pairOverride;

  /// Синтетический урок-окно: разрыв между двумя соседними уроками,
  /// который достаточно длинный, чтобы его показать. У таких уроков
  /// отрицательный id (генерируется на клиенте) и пустые поля, кроме
  /// startTime/endTime. В БД НЕ сохраняется, вычисляется на лету.
  final bool isGap;

  /// Внеурочное занятие из /ec/api/ec_schedule_items («Разговоры о
  /// важном», «Россия — мои горизонты» и т.п.). Отличается источником
  /// данных — обычный урок приходит из /jersey/api/schedule_items.
  /// В UI помечается чипом «внеурочная деятельность», чтобы визуально не смешивать
  /// с обычной программой.
  final bool isEc;

  const Lesson({
    this.id,
    this.secondaryId,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.subjectId,
    this.homeworks = const [],
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

  /// Длительность в минутах. Для окна это длина разрыва.
  int? get durationMinutes {
    final s = _minutes(startTime);
    final e = _minutes(endTime);
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
    id: json['id'] as int?,
    startTime: json['start_time'] as String? ?? '',
    endTime: json['end_time'] as String? ?? '',
    subject: json['subject'] as String? ?? '—',
    subjectId: json['subject_id'] as int?,
    homeworks: decodeHomeworks(json['homework']),
    attachments: _decodeAttachments(json['attachments']),
    teacher: json['teacher'] as String?,
    teacherId: json['teacher_id'] as int?,
    room: json['room'] as String?,
    studentHomeworkIds: _decodeIds(json['student_homework_ids']),
    isEc: json['is_ec'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start_time': startTime,
    'end_time': endTime,
    'subject': subject,
    'subject_id': subjectId,
    'homework': jsonEncode(homeworks),
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

  static List<HomeworkAttachment> _decodeAttachments(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HomeworkAttachment.fromJson)
        .where((a) => a.url.isNotEmpty)
        .toList();
  }

  String get homeworkDisplay =>
      homeworks.isEmpty ? 'не задано' : homeworks.first;

  int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

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
  final startMin = a._minutes(a.endTime);
  final endMin = b._minutes(b.startTime);

  final seen = <String>{};
  final attachments = <HomeworkAttachment>[];
  for (final att in [...a.attachments, ...b.attachments]) {
    if (seen.add(att.url)) attachments.add(att);
  }

  return Lesson(
    id: a.id,
    secondaryId: b.id,
    startTime: a.startTime,
    endTime: b.endTime,
    subject: a.subject,
    subjectId: a.subjectId,
    homeworks: homeworks,
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
