import 'package:flutter/material.dart';

import '../../models/subject_grade.dart';
import '../common/grade_dot.dart';

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
    final allDates = period?.allDates ?? grade.allDates;
    final allComments = period?.allComments ?? grade.allComments;
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
            child: _MiniGradesRow(
              grades: allGrades,
              dates: allDates,
              comments: allComments,
            ),
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
  final List<DateTime?> dates;
  final List<String?> comments;

  const _MiniGradesRow({
    required this.grades,
    this.dates = const [],
    this.comments = const [],
  });

  /// Достаёт i-й элемент, если он есть и совпадает по типу с ожидаемым.
  /// Принимает List<Object?>, чтобы не спотыкаться о вывод типов
  /// (List<DateTime?> / List<String?> отлично сюда подходят).
  T? _at<T>(List<Object?> list, int i) {
    if (i < 0 || i >= list.length) return null;
    final v = list[i];
    return v is T ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) {
      return Text('Нет оценок',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final start = grades.length > 8 ? grades.length - 8 : 0;
    final shown = grades.sublist(start);
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GradeDot(
              value: shown[i],
              size: 22,
              onTap: () => showGradeDetails(
                context,
                value: shown[i],
                receivedAt: _at<DateTime>(dates, start + i),
                comment: _at<String>(comments, start + i),
              ),
            ),
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
              for (var i = 0; i < workType.grades.length; i++)
                GradeDot(
                  value: workType.grades[i],
                  size: 28,
                  onTap: () => showGradeDetails(
                    context,
                    value: workType.grades[i],
                    receivedAt: workType.dateAt(i),
                    comment: workType.commentAt(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}