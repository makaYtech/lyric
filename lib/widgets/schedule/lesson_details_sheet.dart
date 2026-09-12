import 'package:flutter/material.dart';

import '../../models/lesson.dart';

/// Содержимое модалки, которая выезжает снизу по тапу на урок.
/// Ширина — во весь экран; это обеспечивает сам вызов
/// showModalBottomSheet (см. LessonCard._openDetails).
class LessonDetailsSheet extends StatefulWidget {
  final Lesson lesson;

  const LessonDetailsSheet({super.key, required this.lesson});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = widget.lesson;
    final hasTeacher = lesson.teacher != null && lesson.teacher!.isNotEmpty;
    final hasRoom = lesson.room != null && lesson.room!.isNotEmpty;
    final homeworks = lesson.homeworks.isEmpty ? const ['не задано'] : lesson.homeworks;

    return SafeArea(
      top: false, // верхняя часть шторки уже под drag handle, не дублируем
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Text(
              lesson.subject,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),

            // Время + инициалы учителя одной строкой.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                if (hasTeacher)
                  Text(
                    lesson.teacher!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // ДЗ — заголовок
            Text(
              'ДЗ:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),

            // ДЗ — можно пролистать, если заданий на урок несколько.
            // Высота страницы подстраивается под самый длинный текст,
            // чтобы точки-индикаторы не прыгали при свайпе.
            IntrinsicHeight(
              child: SizedBox(
                height: _estimateHeight(theme, homeworks),
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final hw in homeworks)
                      SingleChildScrollView(
                        child: Text(
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
            ),

            if (homeworks.length > 1) ...[
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
          ],
        ),
      ),
    );
  }

  /// Грубая оценка высоты под самый длинный текст ДЗ, чтобы PageView не
  /// приходилось задавать фиксированную высоту "на глаз".
  double _estimateHeight(ThemeData theme, List<String> texts) {
    final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final lineHeight = fontSize * 1.4;
    final longest = texts.fold<int>(0, (m, t) => t.length > m ? t.length : m);
    // ~40 символов в строку при ширине шторки с паддингами — грубо, но
    // достаточно, чтобы не обрезать текст и не оставлять пустоты.
    final lines = (longest / 40).ceil().clamp(1, 8);
    return lineHeight * lines + 8;
  }
}