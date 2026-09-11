import 'package:flutter/material.dart';

import '../models/subject_grade.dart';
import '../widgets/async_state_view.dart';
import '../widgets/subject_grade_card.dart';

class GradesView extends StatefulWidget {
  final List<SubjectGrade>? grades;
  final bool isLoading;
  final String? error;

  const GradesView({
    super.key,
    required this.grades,
    required this.isLoading,
    required this.error,
  });

  @override
  State<GradesView> createState() => _GradesViewState();
}

class _GradesViewState extends State<GradesView> {
  String? _selectedPeriod;

  @override
  void didUpdateWidget(covariant GradesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grades != widget.grades) {
      _validateSelection();
    }
  }

  void _validateSelection() {
    final periods = _collectPeriods(widget.grades);
    if (periods.isEmpty) {
      _selectedPeriod = null;
    } else if (_selectedPeriod == null || !periods.contains(_selectedPeriod)) {
      _selectedPeriod = periods.first;
    }
  }

  /// Собираем уникальные имена периодов по всем предметам и сортируем.
  List<String> _collectPeriods(List<SubjectGrade>? grades) {
    if (grades == null) return const [];
    final set = <String>{};
    for (final s in grades) {
      for (final p in s.periods) {
        set.add(p.name);
      }
    }
    return set.toList()..sort(_comparePeriods);
  }

  /// "1 полугодие" < "2 полугодие" < "10 ..." — по числу, потом по строке.
  static int _comparePeriods(String a, String b) {
    final na = _extractNumber(a);
    final nb = _extractNumber(b);
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.compareTo(b);
  }

  static int? _extractNumber(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  @override
  Widget build(BuildContext context) {
    return AsyncStateView(
      isLoading: widget.isLoading,
      error: widget.error,
      hasData: widget.grades != null && widget.grades!.isNotEmpty,
      contentBuilder: (context) {
        final all = widget.grades!;
        final periods = _collectPeriods(all);
        final selected = _selectedPeriod ??
            (periods.isNotEmpty ? periods.first : null);

        // Предметы, у которых есть оценки за выбранный период.
        final visible = selected == null
            ? all
            : all.where((s) {
          final p = s.periodByName(selected);
          return p != null && p.allGrades.isNotEmpty;
        }).toList();

        final listView = visible.isEmpty
            ? ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SizedBox(height: 80),
            Center(child: Text('Нет оценок за этот период')),
          ],
        )
            : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => SubjectGradeCard(
            grade: visible[i],
            selectedPeriod: selected,
          ),
        );

        return Column(
          children: [
            // Показываем переключатель только если периодов реально > 1.
            if (periods.length > 1)
              _PeriodSwitcher(
                periods: periods,
                selected: selected!,
                onChanged: (p) => setState(() => _selectedPeriod = p),
              ),
            Expanded(child: listView),
          ],
        );
      },
    );
  }
}

class _PeriodSwitcher extends StatelessWidget {
  final List<String> periods;
  final String selected;
  final ValueChanged<String> onChanged;

  const _PeriodSwitcher({
    required this.periods,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: periods.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final p = periods[i];
            return ChoiceChip(
              label: Text(p),
              selected: p == selected,
              onSelected: (_) => onChanged(p),
            );
          },
        ),
      ),
    );
  }
}