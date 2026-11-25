import 'package:flutter/material.dart';

import '../../domain/attendance/attendance.dart';
import '../../domain/schedule/lesson.dart';
import '../../domain/schedule/lesson_grades.dart';
import '../common/absence_dot.dart';
import '../common/attachment_button.dart';
import '../common/copy_all_button.dart';
import '../common/grade_dot.dart';
import '../common/linkable_text.dart';
import '../common/my_work_section.dart';
import '../common/scrollable_sheet_body.dart';

/// Содержимое модалки урока. Высоту контролирует DraggableScrollableSheet
/// снаружи; scrollController нужен, чтобы жест работал на всём содержимом.
///
/// Текст обёрнут в SelectionArea, ссылки в ДЗ открываются в браузере.
class LessonDetailsSheet extends StatefulWidget {
  final Lesson lesson;
  final List<LessonGrade> grades;
  final Attendance? attendance;
  final ScrollController? scrollController;

  const LessonDetailsSheet({
    super.key,
    required this.lesson,
    this.grades = const [],
    this.attendance,
    this.scrollController,
  });

  @override
  State<LessonDetailsSheet> createState() => _LessonDetailsSheetState();
}

class _LessonDetailsSheetState extends State<LessonDetailsSheet> {
  late final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Пустой homeworks[] заменяется плейсхолдером «не задано», чтобы
  /// PageView / Text всегда имели непустой элемент.
  List<String> _homeworksList() {
    final raw = widget.lesson.homeworks;
    return raw.isEmpty ? const ['не задано'] : raw;
  }

  String _currentHomeworkText() {
    final list = _homeworksList();
    if (list.isEmpty) return '';
    final i = _page < list.length ? _page : 0;
    return list[i];
  }

  int _currentStudentHomeworkId() {
    final ids = widget.lesson.studentHomeworkIds;
    if (ids.isEmpty) return 0;
    final i = _page < ids.length ? _page : 0;
    return ids[i];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = widget.lesson;
    final hasTeacher = lesson.teacher != null && lesson.teacher!.isNotEmpty;
    final hasRoom = lesson.room != null && lesson.room!.isNotEmpty;
    final attendance = widget.attendance;
    final homeworks = _homeworksList();

    return ScrollableSheetBody(
      controller: widget.scrollController,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.subject,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${lesson.startTime} – ${lesson.endTime}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                      if (lesson.isEc) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'внеурочная деятельность',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hasRoom) ...[
                    const SizedBox(height: 4),
                    Text(
                      lesson.room!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (widget.grades.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final g in widget.grades)
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
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasTeacher)
                  Text(
                    lesson.teacher!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (attendance != null) ...[
                  const SizedBox(height: 6),
                  AbsenceDot(
                    excused: attendance.isExcused,
                    size: 24,
                    onTap: () => showAbsenceDetails(
                      context,
                      attendance: attendance,
                      subject: lesson.subject,
                      teacher: lesson.teacher,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Text(
                'ДЗ:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            CopyAllButton(text: _currentHomeworkText()),
          ],
        ),
        const SizedBox(height: 6),

        // PageView горизонтальный, внешний скролл вертикальный — жесты
        // не конфликтуют.
        if (homeworks.length == 1)
          LinkableText(
            homeworks.first,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              height: 1.4,
            ),
          )
        else ...[
          SizedBox(
            height: _estimateHeight(theme, homeworks),
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final hw in homeworks)
                  SingleChildScrollView(
                    child: LinkableText(
                      hw,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < homeworks.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ],

        // Индекс PageView совпадает с studentHomeworkIds; у EC-уроков
        // список пуст, и секция скрыта.
        if (_currentStudentHomeworkId() != 0) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          MyWorkSection(
            key: ValueKey(_currentStudentHomeworkId()),
            studentHomeworkId: _currentStudentHomeworkId(),
          ),
        ],

        if (lesson.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            'Файлы',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in lesson.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AttachmentButton(attachments: [a], label: a.name),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// PageView требует явный размер; оцениваем по самому длинному тексту.
  double _estimateHeight(ThemeData theme, List<String> texts) {
    final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final lineHeight = fontSize * 1.4;
    final longest = texts.fold<int>(0, (m, t) => t.length > m ? t.length : m);
    final lines = (longest / 40).ceil().clamp(1, 8);
    return lineHeight * lines + 8;
  }
}
