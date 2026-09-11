import 'package:flutter/material.dart';

import '../models/subject_grade.dart';

class SubjectGradeCard extends StatelessWidget {
  final SubjectGrade grade;

  /// Если задан — карточка показывает только этот период.
  /// Если null — показывает все workTypes из всех периодов.
  final String? selectedPeriod;

  const SubjectGradeCard({
    super.key,
    required this.grade,
    this.selectedPeriod,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final period = selectedPeriod == null
        ? null
        : grade.periodByName(selectedPeriod!);

    final workTypes = period?.workTypes ??
        grade.periods.expand((p) => p.workTypes).toList();
    final avg = period?.average ?? grade.average;
    final allGrades = period?.allGrades ?? grade.allGrades;
    final avgColor = _averageColor(avg);

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  grade.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              _AverageBadge(value: avg, color: avgColor),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _MiniGradesRow(grades: allGrades),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            if (workTypes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Нет оценок за этот период',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...workTypes.map((w) => _WorkTypeRow(workType: w)),
          ],
        ),
      ),
    );
  }

  Color _averageColor(double? avg) {
    if (avg == null || avg == 0) return Colors.grey;
    if (avg >= 4.5) return Colors.green;
    if (avg >= 3.5) return Colors.blue;
    if (avg >= 2.5) return Colors.orange;
    return Colors.red;
  }
}

class _AverageBadge extends StatelessWidget {
  final double? value;
  final Color color;
  const _AverageBadge({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value == null || value == 0 ? '—' : value!.toStringAsFixed(2),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniGradesRow extends StatelessWidget {
  final List<int> grades;
  const _MiniGradesRow({required this.grades});

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) {
      return Text('Нет оценок',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final shown = grades.length > 8 ? grades.sublist(grades.length - 8) : grades;
    return Row(
      children: [
        for (final g in shown)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _GradeDot(value: g, size: 22),
          ),
        if (grades.length > 8)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+${grades.length - 8}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _WorkTypeRow extends StatelessWidget {
  final WorkTypeGrades workType;
  const _WorkTypeRow({required this.workType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = workType.average;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workType.workType,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (avg != null)
                Text(
                  avg.toStringAsFixed(2),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in workType.grades) _GradeDot(value: g, size: 28),
            ],
          ),
        ],
      ),
    );
  }
}

class _GradeDot extends StatelessWidget {
  final int value;
  final double size;
  const _GradeDot({required this.value, required this.size});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(value);
    return Container(
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
  }

  Color _colorFor(int v) {
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
}