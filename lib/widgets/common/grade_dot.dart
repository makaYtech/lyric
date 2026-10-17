import 'package:flutter/material.dart';

import '../shell/adaptive_sheet.dart';

class GradeDot extends StatelessWidget {
  final int value;
  final double size;
  final VoidCallback? onTap;

  /// Вес оценки. 1 или null — обычная. ≥2 — показываем «5²», «5³» и т.п.
  final int? weight;

  const GradeDot({
    super.key,
    required this.value,
    this.size = 28,
    this.onTap,
    this.weight,
  });

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(value);
    final w = weight ?? 1;
    final hasWeight = w > 1;

    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: hasWeight ? 1.5 : 1),
      ),
      child: hasWeight ? _weightedContent(color, w) : _plainContent(color),
    );

    if (onTap == null) return dot;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: dot,
    );
  }

  Widget _plainContent(Color color) => Text(
    '$value',
    style: TextStyle(
      color: color,
      fontSize: size * 0.5,
      fontWeight: FontWeight.w600,
    ),
  );

  /// «5²» — основа чуть мельче обычной, вес — ещё мельче и сверху.
  Widget _weightedContent(Color color, int w) {
    final baseSize = size * 0.42;
    final supSize = size * 0.30;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: baseSize,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: size * 0.02, top: size * 0.03),
          child: Text(
            '$w',
            style: TextStyle(
              color: color,
              fontSize: supSize,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

Color gradeColor(int v) {
  switch (v) {
    case 5:
      return Colors.green;
    case 4:
      return Colors.blue;
    case 3:
      return Colors.orange;
    case 2:
      return Colors.red;
    default:
      return Colors.grey;
  }
}

Future<void> showGradeDetails(
  BuildContext context, {
  required int value,
  required DateTime? receivedAt,
  String? comment,
  String? subject,
  String? workType,
  int? weight,
}) {
  final theme = Theme.of(context);
  final hasComment = comment != null && comment.trim().isNotEmpty;
  final hasSubject = subject != null && subject.trim().isNotEmpty;
  final hasWorkType = workType != null && workType.trim().isNotEmpty;
  final hasWeight = (weight ?? 1) > 1;
  final subtitleParts = <String>[
    if (hasSubject) subject.trim(),
    if (hasWorkType) workType.trim(),
  ];

  return showAdaptiveSheet<void>(
    context,
    builder: (_, _) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GradeDot(value: value, size: 40, weight: weight),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Оценка',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitleParts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitleParts.join(' · '),
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
            Text(
              'Получена',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              receivedAt == null ? '—' : _formatDateTime(receivedAt),
              style: theme.textTheme.titleMedium,
            ),
            if (hasWeight) ...[
              const SizedBox(height: 16),
              Text(
                'Вес',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '×$weight (двойной вес)',
                style: theme.textTheme.titleMedium,
              ),
            ],
            if (hasComment) ...[
              const SizedBox(height: 16),
              Text(
                'Комментарий',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(comment.trim(), style: theme.textTheme.bodyLarge),
            ],
          ],
        ),
      ),
    ),
  );
}

String _formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(d.day)}.${two(d.month)}.${two(d.year)}';
  if (d.hour == 0 && d.minute == 0 && d.second == 0) return date;
  return '$date, ${two(d.hour)}:${two(d.minute)}';
}
