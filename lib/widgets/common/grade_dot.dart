import 'package:flutter/material.dart';

class GradeDot extends StatelessWidget {
  final int value;
  final double size;
  final VoidCallback? onTap;

  const GradeDot({
    super.key,
    required this.value,
    this.size = 28,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(value);
    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          color: color,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (onTap == null) return dot;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: dot,
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
    }) {
  print('GRADE: subject=$subject workType=$workType comment=$comment');
  final theme = Theme.of(context);
  final hasComment = comment != null && comment.trim().isNotEmpty;
  final hasSubject = subject != null && subject.trim().isNotEmpty;
  final hasWorkType = workType != null && workType.trim().isNotEmpty;
  final subtitleParts = <String>[
    if (hasSubject) subject.trim(),
    if (hasWorkType) workType.trim(),
  ];

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
                GradeDot(value: value, size: 40),
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
                      // Подзаголовок: «Алгебра · Контрольная работа».
                      // Появляется, только если снаружи передали subject
                      // и/или workType.
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
  final date = '${two(d.day)}.${two(d.month)}.${d.year}';
  // Время неизвестно — API отдал только дату. Не рисуем «00:00».
  if (d.hour == 0 && d.minute == 0 && d.second == 0) return date;
  return '$date, ${two(d.hour)}:${two(d.minute)}';
}