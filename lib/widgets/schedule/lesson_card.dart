import 'package:flutter/material.dart';

import '../../models/attendance.dart';
import '../../models/lesson.dart';
import '../../models/lesson_grades.dart';
import '../common/absence_dot.dart';
import '../common/grade_dot.dart';
import 'lesson_details_sheet.dart';
import '../shell/adaptive_sheet.dart';
import 'lesson_density.dart';

class LessonCard extends StatelessWidget {
  final Lesson lesson;
  final List<LessonGrade> grades;
  final Attendance? attendance;

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

  final LessonDensity density;

  const LessonCard({
    super.key,
    required this.lesson,
    this.grades = const [],
    this.attendance,
    this.isSelectionMode = false,
    this.selectedLessonIds = const {},
    this.onTap,
    this.onLongPress,
    this.invisible = false,
    this.disableInkWell = false,
    this.changed = false,
    this.density = LessonDensity.comfortable,
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
    return showAdaptiveSheet<void>(
      context,
      draggable: true,
      useSafeArea: true,
      initialSize: 0.5,
      minSize: 0.3,
      maxSize: 1.0,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) => LessonDetailsSheet(
        lesson: lesson,
        grades: grades,
        attendance: attendance,
        scrollController: scrollController!,
      ),
    );
  }

  Widget _comfortableInner(
    BuildContext context,
    ThemeData theme,
    Color dim,
    bool hasTeacher,
  ) {
    return Padding(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
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
          // Предмет + «Н» в правом верхнем углу карточки.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  lesson.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (attendance != null) ...[
                const SizedBox(width: 8),
                AbsenceDot(
                  excused: attendance!.isExcused,
                  size: 24,
                  onTap: () => showAbsenceDetails(
                    context,
                    attendance: attendance!,
                    subject: lesson.subject,
                    teacher: lesson.teacher,
                  ),
                ),
              ],
            ],
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
                    weight: g.weight,
                    onTap: () => showGradeDetails(
                      context,
                      value: g.value,
                      receivedAt: g.receivedAt,
                      subject: lesson.subject,
                      workType: g.workType,
                      weight: g.weight,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Оценки и «Н» одной строкой — для compact/dense.
  List<Widget> _dots(BuildContext context, double size) {
    return [
      for (final g in grades) ...[
        const SizedBox(width: 4),
        GradeDot(
          value: g.value,
          size: size,
          weight: g.weight,
          onTap: () => showGradeDetails(
            context,
            value: g.value,
            receivedAt: g.receivedAt,
            subject: lesson.subject,
            workType: g.workType,
            weight: g.weight,
          ),
        ),
      ],
      if (attendance != null) ...[
        const SizedBox(width: 4),
        AbsenceDot(
          excused: attendance!.isExcused,
          size: size,
          onTap: () => showAbsenceDetails(
            context,
            attendance: attendance!,
            subject: lesson.subject,
            teacher: lesson.teacher,
          ),
        ),
      ],
    ];
  }

  Widget _changedDot(ThemeData theme) => Container(
    width: 6,
    height: 6,
    margin: const EdgeInsets.only(right: 6),
    decoration: BoxDecoration(
      color: theme.colorScheme.error,
      shape: BoxShape.circle,
    ),
  );

  /// Две строки: «время · предмет · оценки» и ниже ДЗ.
  Widget _compactInner(BuildContext context, ThemeData theme, Color dim) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (changed) _changedDot(theme),
              Text(
                lesson.startTime,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: dim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lesson.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (lesson.isPaired) ...[
                const SizedBox(width: 4),
                Icon(Icons.link, size: 14, color: dim),
              ],
              ..._dots(context, 20),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'ДЗ: ${lesson.homeworkDisplay}',
            style: theme.textTheme.bodySmall?.copyWith(color: dim),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Одна строка, как в бумажном дневнике. ДЗ — иконкой с подсказкой
  /// (полный текст — в деталях по клику).
  Widget _denseInner(BuildContext context, ThemeData theme, Color dim) {
    final hasHomework = lesson.homeworks.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          if (changed) _changedDot(theme),
          SizedBox(
            width: 42,
            child: Text(
              lesson.startTime,
              style: theme.textTheme.labelSmall?.copyWith(
                color: dim,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              lesson.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (lesson.isPaired) ...[
            const SizedBox(width: 4),
            Icon(Icons.link, size: 14, color: dim),
          ],
          if (hasHomework) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'ДЗ: ${lesson.homeworkDisplay}',
              child: Icon(Icons.edit_note, size: 18, color: dim),
            ),
          ],
          ..._dots(context, 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final hasTeacher = lesson.teacher != null && lesson.teacher!.isNotEmpty;

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

    final Widget inner = switch (density) {
      LessonDensity.comfortable => _comfortableInner(
        context,
        theme,
        dim,
        hasTeacher,
      ),
      LessonDensity.compact => _compactInner(context, theme, dim),
      LessonDensity.dense => _denseInner(context, theme, dim),
    };

    final content = Card(
      elevation: 0,
      margin: EdgeInsets.symmetric(
        vertical: switch (density) {
          LessonDensity.comfortable => 4,
          LessonDensity.compact => 3,
          LessonDensity.dense => 2,
        },
      ),
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
