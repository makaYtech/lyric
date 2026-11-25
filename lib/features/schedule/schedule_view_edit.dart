part of 'schedule_view.dart';

extension _ScheduleEdit on _ScheduleViewState {
  Future<void> _confirmDelete() async {
    final day = _selectionDay;
    if (day == null) return;
    final selected = _selectedVisibleLessons();
    if (selected.isEmpty) return;
    if (selected.any((l) => l.isGap)) return;

    final idsToDelete = <int>{};
    for (final l in selected) {
      if (l.id != null) idsToDelete.add(l.id!);
      if (l.secondaryId != null) idsToDelete.add(l.secondaryId!);
    }

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          selected.length == 1
              ? 'Удалить урок?'
              : 'Удалить ${selected.length} уроков?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Уроки исчезнут из расписания на этот день. Данные '
                'с сервера не тронутся — правку можно откатить.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final l in selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${l.startTime}–${l.endTime} · ${l.subject}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final callback = widget.onDeleteLessons;
    if (callback == null) return;

    final overrideIds = await callback(day, idsToDelete.toList());
    if (!mounted) return;
    _exitSelection();

    if (overrideIds.isNotEmpty) {
      _showUndoSnackbar(
        overrideIds,
        selected.length == 1
            ? 'Урок удалён'
            : 'Удалено уроков: ${selected.length}',
      );
    }
  }

  Future<void> _handleReorder(
    DateTime dayDate,
    List<Lesson> originalOrder,
    List<Lesson> newOrder,
  ) async {
    _stopAutoScroll();

    final callback = widget.onReorderLessons;
    if (callback == null) return;

    final ids = await callback(dayDate, originalOrder, newOrder);
    if (!mounted) return;

    if (ids.isNotEmpty) {
      _showUndoSnackbar(ids, 'Расписание изменено');
    }
  }

  void _showUndoSnackbar(List<int> overrideIds, String message) {
    final revert = widget.onRevertOverrideIds;
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        action: revert == null
            ? null
            : SnackBarAction(
                label: 'Отменить',
                textColor: theme.colorScheme.inversePrimary,
                onPressed: () {
                  messenger.hideCurrentSnackBar();
                  revert(overrideIds);
                },
              ),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) messenger.hideCurrentSnackBar();
    });
  }

  Future<void> _showOverridesSheet() async {
    final loadOverrides = widget.onLoadWeekOverrides;
    final loadRaw = widget.onLoadWeekRawLessons;
    final revertOne = widget.onRevertOverride;
    final revertWeek = widget.onRevertWeek;
    if (loadOverrides == null || loadRaw == null) return;

    final overrides = await loadOverrides();
    final rawDays = await loadRaw();
    if (!mounted) return;

    await showAdaptiveSheet<void>(
      context,
      draggable: true,
      useSafeArea: true,
      initialSize: 0.6,
      minSize: 0.3,
      maxSize: 0.95,
      snapSizes: const [0.6, 0.95],
      builder: (context, _) => ScheduleOverridesSheet(
        overrides: overrides,
        rawDays: rawDays,
        onRevertOverride: revertOne ?? (_) async {},
        onRevertWeek: revertWeek ?? () async {},
        onReload: () async {
          final o = await loadOverrides();
          final r = await loadRaw();
          return (overrides: o, rawDays: r);
        },
      ),
    );
  }
}
