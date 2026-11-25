import '../../domain/schedule/bells_timetable.dart';
import '../../domain/schedule/lesson.dart';
import '../settings/schedule_prefs.dart';
import '../util/date_time.dart';

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
    final firstStart = minutesFromHhmm(lessons.first.startTime);
    if (firstStart != null) {
      final gap = firstStart - dayStart;
      if (gap > threshold) {
        out.add(
          Lesson(
            id: gapId--,
            startTime: _minToHhmm(dayStart),
            endTime: lessons.first.startTime,
            subject: 'Окно',
            isGap: true,
          ),
        );
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

    final endA = minutesFromHhmm(a.endTime);
    final startB = minutesFromHhmm(b.startTime);
    if (endA == null || startB == null) continue;

    final gap = startB - endA;
    if (gap <= threshold) continue;

    out.add(
      Lesson(
        id: gapId--,
        startTime: a.endTime,
        endTime: b.startTime,
        subject: 'Окно',
        isGap: true,
      ),
    );
  }

  return out;
}

int _resolveDayStart(BellsTimetable? bells, int? weekDayId) {
  if (bells == null || weekDayId == null) return _fallbackDayStartMinutes;
  final s = bells.firstLessonStart(weekDayId);
  if (s == null) return _fallbackDayStartMinutes;
  return minutesFromHhmm(s) ?? _fallbackDayStartMinutes;
}

String _minToHhmm(int total) => hhmm(total ~/ 60, total % 60);
