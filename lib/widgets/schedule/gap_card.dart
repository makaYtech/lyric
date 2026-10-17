import 'package:flutter/material.dart';

import '../../models/lesson.dart';
import 'lesson_density.dart';

/// Компактная карточка окна между уроками.
class GapCard extends StatelessWidget {
  final Lesson gap;
  final bool isSelectionMode;
  final bool isSelected;

  /// Подсветка во время drag: урок наведён на это окно и его можно
  /// бросить сюда. Красим в цвет обводки primary.
  final bool highlighted;

  final VoidCallback? onTap;

  final LessonDensity density;

  const GapCard({
    super.key,
    required this.gap,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.highlighted = false,
    this.onTap,
    this.density = LessonDensity.comfortable,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final minutes = gap.durationMinutes ?? 0;

    final selectedColor = theme.colorScheme.primaryContainer;
    final normalColor = theme.colorScheme.surfaceContainerHighest;

    final bg = isSelected ? selectedColor : normalColor;

    final border = highlighted
        ? Border.all(color: theme.colorScheme.primary, width: 2)
        : (isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null);
    final icon = Icon(
      highlighted ? Icons.arrow_downward : Icons.more_horiz,
      size: 18,
      color: highlighted ? theme.colorScheme.primary : dim,
    );

    final Widget card;
    if (density.isComfortable) {
      card = Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Окно',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: dim,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${gap.startTime} – ${gap.endTime} · ${_fmt(minutes)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      // Компактно: одна строка «Окно · 10:05 – 10:50 · 45 мин».
      card = Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: border,
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Окно · ${gap.startTime} – ${gap.endTime} · ${_fmt(minutes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: dim),
              ),
            ),
          ],
        ),
      );
    }

    final faded = isSelectionMode && !isSelected;
    final content = faded
        ? AnimatedOpacity(
            opacity: 0.45,
            duration: const Duration(milliseconds: 150),
            child: card,
          )
        : card;

    if (onTap == null || !isSelectionMode) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }

  static String _fmt(int minutes) {
    if (minutes <= 0) return '—';
    if (minutes < 60) return '$minutes мин';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h ч';
    return '$h ч $m мин';
  }
}
