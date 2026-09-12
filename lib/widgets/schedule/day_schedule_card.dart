import 'package:flutter/material.dart';

import '../../core/settings/schedule_prefs.dart';
import '../../models/day_schedule.dart';
import '../../models/lesson.dart';
import '../../models/lesson_grades.dart';
import 'lesson_card.dart';

class DayScheduleCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = highlightToday && _isToday(day.date);

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
                final lessons =
                merge ? mergeLessonPairs(day.lessons) : day.lessons;
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
                        grades: grades.forLesson(l),
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