import 'package:flutter/material.dart';

import '../../models/attendance.dart';

/// Кружок с «Н» — отсутствие на уроке. Визуально повторяет GradeDot,
/// но это не оценка: цвет — только про уважительность причины.
///   уважительная (absence_reason_id == 2) — жёлтый;
///   иначе / null — красный.
class AbsenceDot extends StatelessWidget {
  final bool excused;
  final double size;
  final VoidCallback? onTap;

  const AbsenceDot({
    super.key,
    required this.excused,
    this.size = 24,
    this.onTap,
  });

  static Color colorFor({required bool excused}) =>
      excused ? Colors.amber.shade700 : Colors.red;

  @override
  Widget build(BuildContext context) {
    final color = colorFor(excused: excused);
    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        'Н',
        style: TextStyle(
          color: color,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
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

/// Модалка по тапу на «Н». Дата, тип (уваж./без уваж.), учитель.
Future<void> showAbsenceDetails(
  BuildContext context, {
  required Attendance attendance,
  String? subject,
  String? teacher,
}) {
  final theme = Theme.of(context);
  final color = AbsenceDot.colorFor(excused: attendance.isExcused);

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
                AbsenceDot(excused: attendance.isExcused, size: 40),
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
                      if (subject != null && subject.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subject,
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
            _LabelValue(
              label: 'Дата',
              value: attendance.date == null
                  ? '—'
                  : _formatDate(attendance.date!),
            ),
            const SizedBox(height: 12),
            _LabelValue(
              label: 'Тип',
              value: attendance.isExcused
                  ? 'Пропуск по причине'
                  : 'Пропуск без уважительной причины',
              valueColor: color,
            ),
            if (teacher != null && teacher.isNotEmpty) ...[
              const SizedBox(height: 12),
              _LabelValue(label: 'Учитель', value: teacher),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _LabelValue({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${two(d.year)}';
}
