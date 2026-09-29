import 'package:flutter/material.dart';

import '../../models/subject_grade.dart';
import '../common/grade_dot.dart';

class SubjectGradeCard extends StatefulWidget {
  final SubjectGrade grade;
  final String? selectedPeriod;

  const SubjectGradeCard({super.key, required this.grade, this.selectedPeriod});

  @override
  State<SubjectGradeCard> createState() => _SubjectGradeCardState();
}

class _SubjectGradeCardState extends State<SubjectGradeCard> {
  // Кэш плоского списка оценок. Пересчитываем только когда меняется
  // сам SubjectGrade (identical) или выбранный период. ExpansionTile
  // раскрывается/сворачивается — пропсы те же, кэш живёт.
  List<_MiniGradeEntry>? _cachedEntries;
  SubjectGrade? _cachedEntriesFor;
  String? _cachedEntriesPeriod;

  List<_MiniGradeEntry> _entries() {
    final sameGrade = identical(_cachedEntriesFor, widget.grade);
    final samePeriod = _cachedEntriesPeriod == widget.selectedPeriod;
    if (sameGrade && samePeriod && _cachedEntries != null) {
      return _cachedEntries!;
    }
    final period = widget.selectedPeriod == null
        ? null
        : widget.grade.periodByName(widget.selectedPeriod!);
    final workTypes =
        period?.workTypes ??
        widget.grade.periods.expand((p) => p.workTypes).toList();
    _cachedEntries = _collectEntries(workTypes);
    _cachedEntriesFor = widget.grade;
    _cachedEntriesPeriod = widget.selectedPeriod;
    return _cachedEntries!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = widget.grade;

    final period = widget.selectedPeriod == null
        ? null
        : grade.periodByName(widget.selectedPeriod!);

    final workTypes =
        period?.workTypes ?? grade.periods.expand((p) => p.workTypes).toList();
    final avg = period?.average ?? grade.average;
    final entries = _entries();
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _AverageBadge(value: avg, color: avgColor),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _MiniGradesRow(entries: entries, subject: grade.name),
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
              ...workTypes.map(
                (w) => _WorkTypeRow(workType: w, subject: grade.name),
              ),
          ],
        ),
      ),
    );
  }

  /// Собираем плоский список оценок с сохранением типа работы каждой.
  static List<_MiniGradeEntry> _collectEntries(List<WorkTypeGrades> workTypes) {
    final out = <_MiniGradeEntry>[];
    for (final w in workTypes) {
      for (var i = 0; i < w.grades.length; i++) {
        out.add(
          _MiniGradeEntry(
            value: w.grades[i],
            receivedAt: i < w.dates.length ? w.dates[i] : null,
            comment: w.commentAt(i),
            workType: w.workType,
          ),
        );
      }
    }
    return out;
  }

  Color _averageColor(double? avg) {
    if (avg == null || avg == 0) return Colors.grey;
    if (avg >= 4.5) return Colors.green;
    if (avg >= 3.5) return Colors.blue;
    if (avg >= 2.5) return Colors.orange;
    return Colors.red;
  }
}

/// Одна оценка в мини-строке, со всеми сопутствующими данными.
class _MiniGradeEntry {
  final int value;
  final DateTime? receivedAt;
  final String? comment;
  final String? workType;

  const _MiniGradeEntry({
    required this.value,
    this.receivedAt,
    this.comment,
    this.workType,
  });
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        value == null || value == 0 ? '—' : value!.toStringAsFixed(2),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MiniGradesRow extends StatelessWidget {
  final List<_MiniGradeEntry> entries;
  final String? subject;

  const _MiniGradesRow({required this.entries, this.subject});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text('Нет оценок', style: Theme.of(context).textTheme.bodySmall);
    }
    final start = entries.length > 8 ? entries.length - 8 : 0;
    final shown = entries.sublist(start);
    return Row(
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GradeDot(
              value: e.value,
              size: 22,
              onTap: () => showGradeDetails(
                context,
                value: e.value,
                receivedAt: e.receivedAt,
                comment: e.comment,
                subject: subject,
                workType: e.workType,
              ),
            ),
          ),
        if (entries.length > 8)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+${entries.length - 8}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _WorkTypeRow extends StatelessWidget {
  final WorkTypeGrades workType;
  final String? subject;

  const _WorkTypeRow({required this.workType, this.subject});

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
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
                    subject: subject,
                    workType: workType.workType,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
