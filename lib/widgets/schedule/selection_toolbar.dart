import 'package:flutter/material.dart';

/// Floating-панель расписания в режиме выделения. Кнопки [actions]
/// подставляются снаружи, чтобы панель расширялась без переписывания.
class ScheduleSelectionToolbar extends StatelessWidget {
  /// Сколько видимых (с учётом merge) уроков выделено.
  final int selectedCount;

  /// Кнопки действий.
  final List<Widget> actions;

  /// «Отменить и выйти из режима выделения».
  final VoidCallback onCancel;

  const ScheduleSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.actions,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      color: theme.colorScheme.secondaryContainer,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              tooltip: 'Отменить',
              color: theme.colorScheme.onSecondaryContainer,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '$selectedCount',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
