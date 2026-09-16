import 'package:flutter/material.dart';

import '../../models/day_schedule.dart';
import '../../models/lesson.dart';
import '../../models/schedule_override.dart';
import '../../core/util/labels.dart';

/// Модалка «Правки недели». Список всех override'ов за текущую неделю,
/// сгруппированный по дням. У каждой правки — кнопка «Вернуть».
/// Внизу — «Откатить всё за неделю».
///
/// Тексты правок строятся по сырым (не смердженным) урокам: для удалённого
/// урока его в смердженных данных уже нет, а показать «Удалён: 09:00
/// Алгебра» хочется.
class ScheduleOverridesSheet extends StatefulWidget {
  final List<ScheduleOverride> overrides;
  final List<DaySchedule> rawDays;
  final Future<void> Function(int id) onRevertOverride;
  final Future<void> Function() onRevertWeek;
  final Future<({List<ScheduleOverride> overrides, List<DaySchedule> rawDays})>
  Function() onReload;

  const ScheduleOverridesSheet({
    super.key,
    required this.overrides,
    required this.rawDays,
    required this.onRevertOverride,
    required this.onRevertWeek,
    required this.onReload,
  });

  @override
  State<ScheduleOverridesSheet> createState() =>
      _ScheduleOverridesSheetState();
}

class _ScheduleOverridesSheetState extends State<ScheduleOverridesSheet> {
  late List<ScheduleOverride> _overrides = widget.overrides;
  late List<DaySchedule> _rawDays = widget.rawDays;
  bool _busy = false;

  /// Урок по id (ищем и по primary, и по secondary).
  Lesson? _findRaw(int lessonId) {
    for (final d in _rawDays) {
      for (final l in d.lessons) {
        if (l.id == lessonId) return l;
        if (l.secondaryId == lessonId) return l;
      }
    }
    return null;
  }

  Future<void> _revertOne(int id) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRevertOverride(id);
      final fresh = await widget.onReload();
      if (!mounted) return;
      setState(() {
        _overrides = fresh.overrides;
        _rawDays = fresh.rawDays;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revertWeek() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Откатить всё за неделю?'),
        content: Text(
          'Будет удалено правок: ${_overrides.length}. '
              'Расписание вернётся к серверному варианту.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Откатить всё'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.onRevertWeek();
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_overrides.isEmpty) {
      return SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'На этой неделе правок нет',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Расписание ровно такое, каким его отдал сервер.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            ),
          )
        )
      );
    }

    final byDate = <DateTime, List<ScheduleOverride>>{};
    for (final o in _overrides) {
      byDate.putIfAbsent(o.date, () => []).add(o);
    }
    final sortedDays = byDate.keys.toList()..sort();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Правки недели',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              children: [
                for (final day in sortedDays) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                    child: Text(
                      _dayLabel(day),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  for (final o in byDate[day]!)
                    _OverrideRow(
                      item: o,
                      rawLesson: _findRaw(o.primaryLessonId),
                      secondaryRaw: o.secondaryLessonId == null
                          ? null
                          : _findRaw(o.secondaryLessonId!),
                      findRaw: _findRaw,
                      onRevert: _busy ? null : () => _revertOne(o.id!),
                    ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _revertWeek,
                    icon: const Icon(Icons.restore, size: 18),
                    label: Text('Откатить всё (${_overrides.length})'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final weekday = kWeekdaysFull[d.weekday - 1];
    final month = kMonthsGenitive[d.month - 1];
    return '$weekday, ${d.day} $month';
  }
}

/// Одна строка правки. Поле называется `item`, а НЕ `override` — потому
/// что `override` шадоуит аннотацию `@override` из dart:core.
class _OverrideRow extends StatelessWidget {
  final ScheduleOverride item;
  final Lesson? rawLesson;
  final Lesson? secondaryRaw;

  /// Поиск сырого урока по id. Нужен для kind'а reorder, где в payload
  /// лежит список id, а не один.
  final Lesson? Function(int lessonId) findRaw;

  final VoidCallback? onRevert;

  const _OverrideRow({
    required this.item,
    required this.rawLesson,
    required this.secondaryRaw,
    required this.findRaw,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, text) = _describe();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: onRevert,
                child: const Text('Вернуть'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String) _describe() {
    switch (item.kind) {
      case ScheduleOverrideKind.delete:
        final l = rawLesson;
        final subject = l?.subject ?? 'урок';
        final time = l == null ? '' : '${l.startTime}–${l.endTime} · ';
        return (Icons.delete_outline, 'Удалён: $time$subject');

      case ScheduleOverrideKind.move:
        final l = rawLesson;
        final subject = l?.subject ?? 'урок';
        final from = l?.startTime ?? '?';
        final to = _payloadStart() ?? '?';
        return (Icons.swap_vert, 'Перемещён: $subject ($from → $to)');

      case ScheduleOverrideKind.pairBreak:
        final a = rawLesson;
        final b = secondaryRaw;
        final subject = a?.subject ?? b?.subject ?? 'пара';
        return (Icons.call_split, 'Разъединена пара: $subject');

      case ScheduleOverrideKind.pairMake:
        final a = rawLesson;
        final b = secondaryRaw;
        final subject = a?.subject ?? b?.subject ?? 'уроки';
        return (Icons.merge, 'Объединены в пару: $subject');

      case ScheduleOverrideKind.reorder:
        final order = item.reorderOrder();
        final names = order
            .map((id) => findRaw(id)?.subject ?? '?')
            .toList();
        return (Icons.swap_vert, 'Перестановка: ${names.join(' → ')}');
    }
  }

  String? _payloadStart() {
    final p = item.payload;
    if (p == null) return null;
    final m = RegExp(r'"start_time"\s*:\s*"([^"]+)"').firstMatch(p);
    return m?.group(1);
  }
}