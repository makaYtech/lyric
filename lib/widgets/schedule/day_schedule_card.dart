import 'package:flutter/material.dart';

import '../../core/settings/schedule_prefs.dart';
import '../../models/day_schedule.dart';
import '../../models/lesson.dart';
import '../../models/lesson_grades.dart';
import 'lesson_card.dart';

class DayScheduleCard extends StatefulWidget {
  final DaySchedule day;
  final bool highlightToday;
  final LessonGradesLookup grades;

  const DayScheduleCard({
    super.key,
    required this.day,
    this.highlightToday = true,
    this.grades = LessonGradesLookup.empty,
  });

  @override
  State<DayScheduleCard> createState() => _DayScheduleCardState();
}

class _DayScheduleCardState extends State<DayScheduleCard> {
  // Кэш объединённых пар. Пересчитываем только при смене day.lessons.
  List<Lesson>? _mergedCache;
  List<Lesson>? _mergedFor;

  List<Lesson> _merged() {
    if (identical(_mergedFor, widget.day.lessons) && _mergedCache != null) {
      return _mergedCache!;
    }
    _mergedCache = mergeLessonPairs(widget.day.lessons);
    _mergedFor = widget.day.lessons;
    return _mergedCache!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = widget.day;
    final isToday = widget.highlightToday && _isToday(day.date);

    final todayTint = Color.alphaBlend(
      theme.colorScheme.primary.withOpacity(0.10),
      theme.colorScheme.surface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                day.weekdayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isToday ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                day.dateLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'сегодня',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Card(
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          color: isToday ? todayTint : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ValueListenableBuilder<bool>(
              valueListenable: SchedulePrefs.mergePairs,
              builder: (context, merge, _) {
                final lessons = merge ? _merged() : day.lessons;
                return lessons.isEmpty
                    ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Нет расписания',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in lessons)
                      LessonCard(
                        lesson: l,
                        grades: widget.grades.forLesson(l),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}