part of 'schedule_view.dart';

extension _ScheduleActions on _ScheduleViewState {
  Future<void> _handleDropOnGap(
    DateTime day,
    Lesson dragged,
    Lesson gap,
  ) async {
    final bells = widget.bells;
    final moveCb = widget.onMoveLessons;
    if (bells == null || moveCb == null) {
      _showSnack('Расписание звонков не загружено — не могу найти слот');
      return;
    }

    final ids = <int>[];
    if (dragged.id != null) ids.add(dragged.id!);
    if (dragged.secondaryId != null) ids.add(dragged.secondaryId!);
    if (ids.isEmpty) return;

    final slots = bells.slotsInsideInterval(
      day.weekday,
      gap.startTime,
      gap.endTime,
    );

    if (dragged.isPaired && ids.length >= 2) {
      final pairs = <({Bell a, Bell b})>[];
      for (var i = 0; i + 1 < slots.length; i++) {
        final a = slots[i];
        final b = slots[i + 1];
        final aOrd = a.studyOrdinal;
        final bOrd = b.studyOrdinal;
        if (aOrd != null && bOrd != null && bOrd == aOrd + 1) {
          pairs.add((a: a, b: b));
        }
      }

      if (pairs.isEmpty) {
        if (slots.isEmpty) {
          _showSnack('Паре нужно два урока подряд — в этом окне нет слотов');
        } else if (slots.length == 1) {
          _showSnack(
            'Паре нужно два урока подряд — в этом окне только один слот',
          );
        } else {
          _showSnack(
            'Паре нужно два подряд идущих слота — в этом окне таких нет',
          );
        }
        return;
      }

      ({Bell a, Bell b})? chosen;
      if (pairs.length == 1) {
        chosen = pairs.first;
      } else {
        chosen = await _showSlotPairDialog(dragged, pairs);
      }
      if (chosen == null || !mounted) return;

      final moves = <({int lessonId, String startTime, String endTime})>[
        (
          lessonId: ids[0],
          startTime: chosen.a.beginTime,
          endTime: chosen.a.endTime,
        ),
        (
          lessonId: ids[1],
          startTime: chosen.b.beginTime,
          endTime: chosen.b.endTime,
        ),
      ];

      _exitSelection();
      final overrideIds = await moveCb(day, moves);
      if (!mounted) return;
      if (overrideIds.isNotEmpty) {
        _showUndoSnackbar(overrideIds, 'Пара перенесена');
      }
      return;
    }

    if (slots.isEmpty) {
      _showSnack('В этом окне нет слотов, куда можно поставить урок');
      return;
    }

    Bell? chosen;
    if (slots.length == 1) {
      chosen = slots.first;
    } else {
      chosen = await _showSlotDialog(dragged, slots);
    }
    if (chosen == null || !mounted) return;

    final moves = <({int lessonId, String startTime, String endTime})>[
      (lessonId: ids[0], startTime: chosen.beginTime, endTime: chosen.endTime),
    ];

    _exitSelection();
    final overrideIds = await moveCb(day, moves);
    if (!mounted) return;
    if (overrideIds.isNotEmpty) {
      _showUndoSnackbar(overrideIds, 'Урок перенесён');
    }
  }

  Future<Bell?> _showSlotDialog(Lesson lesson, List<Bell> slots) {
    final theme = Theme.of(context);
    return showDialog<Bell>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Куда поставить «${lesson.subject}»?'),
        children: [
          for (final slot in slots)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(slot),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${slot.beginTime} – ${slot.endTime}'
                    '${slot.studyOrdinal != null ? " · урок ${slot.studyOrdinal}" : ""}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Время берётся из расписания звонков',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<({Bell a, Bell b})?> _showSlotPairDialog(
    Lesson lesson,
    List<({Bell a, Bell b})> pairs,
  ) {
    final theme = Theme.of(context);
    return showDialog<({Bell a, Bell b})>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Куда поставить пару «${lesson.subject}»?'),
        children: [
          for (final p in pairs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${p.a.beginTime} – ${p.b.endTime}',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Пара займёт два подряд идущих слота',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _breakSelectedPair() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.length != 1) return;

    final lesson = selected.first;
    final primaryId = lesson.id;
    final secondaryId = lesson.secondaryId;
    if (primaryId == null || secondaryId == null) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Разъединить пару?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lesson.subject,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lesson.startTime}–${lesson.endTime}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Пара распадётся на два отдельных урока. Правку можно '
              'откатить.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Разъединить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onBreakPair;
    if (callback == null) return;

    await callback(day, primaryId, secondaryId);
    if (!mounted) return;
    _exitSelection();
  }

  Future<void> _makeSelectedPair() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.length != 2) return;

    final a = selected[0];
    final b = selected[1];
    final aId = a.id;
    final bId = b.id;
    if (aId == null || bId == null) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Объединить в пару?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in [a, b])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${l.startTime}–${l.endTime} · ${l.subject}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Уроки будут показаны одной карточкой как пара. Правку '
              'можно откатить.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Объединить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onMakePair;
    if (callback == null) return;

    await callback(day, aId, bId);
    if (!mounted) return;
    _exitSelection();
  }
}
