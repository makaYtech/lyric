import 'dart:convert';

class Lesson {
  /// id урока из schedule_items — ключ строки в БД и ключ, по которому
  /// матчатся оценки (Mark.scheduleLessonId == Lesson.id).
  final int? id;
  /// Заполняется только у пары (см. mergeLessonPairs): id второго урока,
  /// чтобы оценки, привязанные к нему, тоже подтянулись в паре.
  /// Нигде не сохраняется — при загрузке из БД пара собирается заново.
  final int? secondaryId;
  final String startTime;
  final String endTime;
  final String subject;
  /// Числовой id предмета — на всякий случай, если матч по id урока не сработал.
  final int? subjectId;
  final List<String> homeworks;
  final String? teacher;
  final String? room;
  final bool isPaired;
  final int? breakMinutes;

  const Lesson({
    this.id,
    this.secondaryId,
    required this.startTime,
    required this.endTime,
    required this.subject,
    this.subjectId,
    this.homeworks = const [],
    this.teacher,
    this.room,
    this.isPaired = false,
    this.breakMinutes,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
    id: json['id'] as int?,
    startTime: json['start_time'] as String? ?? '',
    endTime: json['end_time'] as String? ?? '',
    subject: json['subject'] as String? ?? '—',
    subjectId: json['subject_id'] as int?,
    homeworks: decodeHomeworks(json['homework']),
    teacher: json['teacher'] as String?,
    room: json['room'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start_time': startTime,
    'end_time': endTime,
    'subject': subject,
    'subject_id': subjectId,
    'homework': jsonEncode(homeworks),
    'teacher': teacher,
    'room': room,
  };

  /// Раньше в БД/кэше лежала одна строка ДЗ, теперь — JSON-список.
  static List<String> decodeHomeworks(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.whereType<String>().toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {
        // не JSON — значит старый формат, одна строка ДЗ.
      }
      return [raw];
    }
    return const [];
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
}

/// Объединяет подряд идущие одинаковые уроки (тот же предмет, учитель,
/// кабинет) в одну пару. Сохраняет id второго урока в secondaryId —
/// чтобы оценки, привязанные ко второму уроку, тоже попали в пару.
List<Lesson> mergeLessonPairs(List<Lesson> lessons) {
  final result = <Lesson>[];
  var i = 0;
  while (i < lessons.length) {
    final a = lessons[i];
    if (i + 1 < lessons.length && _sameSlot(a, lessons[i + 1])) {
      final b = lessons[i + 1];
      final homeworks = <String>{...a.homeworks, ...b.homeworks}.toList();
      final startMin = a._minutes(a.endTime);
      final endMin = b._minutes(b.startTime);
      result.add(Lesson(
        id: a.id,
        secondaryId: b.id,
        startTime: a.startTime,
        endTime: b.endTime,
        subject: a.subject,
        subjectId: a.subjectId,
        homeworks: homeworks,
        teacher: a.teacher,
        room: a.room,
        isPaired: true,
        breakMinutes:
        (startMin != null && endMin != null) ? endMin - startMin : null,
      ));
      i += 2;
    } else {
      result.add(a);
      i += 1;
    }
  }
  return result;
}

bool _sameSlot(Lesson a, Lesson b) =>
    a.subject == b.subject && a.teacher == b.teacher && a.room == b.room;