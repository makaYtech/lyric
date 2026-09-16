import '../../models/bells_timetable.dart';
import '../../models/lesson.dart';
import '../settings/schedule_prefs.dart';

/// Фоллбэк-начало дня, если bells недоступны.
const _fallbackDayStartMinutes = 8 * 60 + 30; // 8:30

/// Вставляет окна в список уроков дня.
List<Lesson> injectGaps(
    List<Lesson> lessons, {
      BellsTimetable? bells,
      int? weekDayId,
    }) {
  if (!SchedulePrefs.showGaps.value) return lessons;

  final threshold = SchedulePrefs.gapThresholdMinutes.value;
  final dayStart = _resolveDayStart(bells, weekDayId);
  final out = <Lesson>[];
  var gapId = -1;

  // Окно перед первым уроком.
  if (lessons.isNotEmpty) {
    final firstStart = _toMin(lessons.first.startTime);
    if (firstStart != null) {
      final gap = firstStart - dayStart;
      if (gap > threshold) {
        out.add(Lesson(
          id: gapId--,
          startTime: _minToHhmm(dayStart),
          endTime: lessons.first.startTime,
          subject: 'Окно',
          isGap: true,
        ));
      }
    }
  }

  // Окна между уроками.
  for (var i = 0; i < lessons.length; i++) {
    out.add(lessons[i]);
    if (i + 1 >= lessons.length) break;

    final a = lessons[i];
    final b = lessons[i + 1];
    if (a.isGap || b.isGap) continue;

    final endA = _toMin(a.endTime);
    final startB = _toMin(b.startTime);
    if (endA == null || startB == null) continue;

    final gap = startB - endA;
    if (gap <= threshold) continue;

    out.add(Lesson(
      id: gapId--,
      startTime: a.endTime,
      endTime: b.startTime,
      subject: 'Окно',
      isGap: true,
    ));
  }

  return out;
}

int _resolveDayStart(BellsTimetable? bells, int? weekDayId) {
  if (bells == null || weekDayId == null) return _fallbackDayStartMinutes;
  final s = bells.firstLessonStart(weekDayId);
  if (s == null) return _fallbackDayStartMinutes;
  final m = _toMin(s);
  return m ?? _fallbackDayStartMinutes;
}

int? _toMin(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _minToHhmm(int total) {
  final h = total ~/ 60;
  final m = total % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}