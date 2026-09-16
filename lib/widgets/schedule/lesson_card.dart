import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import '../../models/lesson_grades.dart';
import '../common/grade_dot.dart';
import 'lesson_details_sheet.dart';

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final List<LessonGrade> grades;

  final bool isSelectionMode;
  final Set<int> selectedLessonIds;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Полностью невидимая карточка (opacity 0). Для оригинала на месте
  /// во время drag.
  final bool invisible;

  /// Полностью убрать InkWell из дерева. Нужно для drag-eligible уроков.
  final bool disableInkWell;

  /// Урок затронут правкой (move/delete/pair*/reorder).
  final bool changed;

  const LessonCard({
    super.key,
    required this.lesson,
    this.grades = const [],
    this.isSelectionMode = false,
    this.selectedLessonIds = const {},
    this.onTap,
    this.onLongPress,
    this.invisible = false,
    this.disableInkWell = false,
    this.changed = false,
  });

  bool get _isSelected {
    final id = lesson.id;
    if (id == null) return false;
    if (!selectedLessonIds.contains(id)) return false;
    final s = lesson.secondaryId;
    if (s != null && !selectedLessonIds.contains(s)) return false;
    return true;
  }

  Future<void> _openDetails(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
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
    final absences = grades.where((g) => g.isAbsence).toList();

    final selected = _isSelected;
    final faded = isSelectionMode && !selected;

    final cardColor = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: selected
          ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
          : BorderSide.none,
    );

    final inner = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (changed) ...[
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
              if (hasTeacher || absences.isNotEmpty) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (absences.isNotEmpty)
                      _AbsenceBadge(
                        onTap: () => showAbsenceDetails(
                          context,
                          lesson: lesson,
                          grades: absences,
                        ),
                      ),
                    if (hasTeacher)
                      Padding(
                        padding: EdgeInsets.only(
                          top: absences.isNotEmpty ? 2 : 0,
                        ),
                        child: Text(
                          lesson.teacher!,
                          style:
                          theme.textTheme.bodySmall?.copyWith(color: dim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
          if (grades.where((g) => !g.isAbsence).isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final g in grades.where((g) => !g.isAbsence))
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
    );

    final content = Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: cardColor,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: disableInkWell
          ? inner
          : InkWell(
        onTap: onTap ?? () => _openDetails(context),
        onLongPress: onLongPress,
        child: inner,
      ),
    );

    final double opacity;
    if (invisible) {
      opacity = 0;
    } else if (faded) {
      opacity = 0.45;
    } else {
      opacity = 1.0;
    }

    if (opacity >= 1.0) return content;
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 150),
      child: content,
    );
  }
}

class _AbsenceBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _AbsenceBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.error, width: 1),
        ),
        child: Text(
          'Н',
          style: TextStyle(
            color: theme.colorScheme.error,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Future<void> showAbsenceDetails(
    BuildContext context, {
      required Lesson lesson,
      required List<LessonGrade> grades,
    }) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Text(
                    'Н',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Отсутствие',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          lesson.subject,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < grades.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              _AbsenceRow(grade: grades[i], lesson: lesson),
            ],
          ],
        ),
      ),
    ),
  );
}

class _AbsenceRow extends StatelessWidget {
  final LessonGrade grade;
  final Lesson lesson;

  const _AbsenceRow({required this.grade, required this.lesson});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Получено',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          grade.receivedAt == null ? '—' : _formatDate(grade.receivedAt!),
          style: theme.textTheme.titleMedium,
        ),
        if (grade.workType != null && grade.workType!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Форма контроля',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(grade.workType!, style: theme.textTheme.bodyLarge),
        ],
        if (lesson.teacher != null && lesson.teacher!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Учитель',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(lesson.teacher!, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
          '${d.month.toString().padLeft(2, '0')}.'
          '${d.year}';
}