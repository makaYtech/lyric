import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../../models/lesson_grades.dart';
import '../common/grade_dot.dart';
import 'lesson_details_sheet.dart';

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final List<LessonGrade> grades;

  const LessonCard({
    super.key,
    required this.lesson,
    this.grades = const [],
  });

  Future<void> _openDetails(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        // Стартуем в половине экрана, минимум — 0.3 (чтобы не схлопнуть
        // в полоску), максимум — во весь экран. snap даёт «прыжок»
        // между 0.5 и 1.0 при отпускании, как в типичных шторках.
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.5, 1.0],
        expand: false,
        builder: (context, scrollController) => LessonDetailsSheet(
          lesson: lesson,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final hasTeacher = lesson.teacher != null && lesson.teacher!.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${lesson.startTime} – ${lesson.endTime}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: dim,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (lesson.isPaired) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        lesson.breakMinutes != null
                            ? 'пара · перемена ${lesson.breakMinutes} мин'
                            : 'пара',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                lesson.subject,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'ДЗ: ${lesson.homeworkDisplay}',
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasTeacher) ...[
                    const SizedBox(width: 12),
                    Text(
                      lesson.teacher!,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
              if (grades.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final g in grades)
                      GradeDot(
                        value: g.value,
                        size: 24,
                        onTap: () => showGradeDetails(
                          context,
                          value: g.value,
                          receivedAt: g.receivedAt,
                          subject: lesson.subject,
                          workType: g.workType,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}