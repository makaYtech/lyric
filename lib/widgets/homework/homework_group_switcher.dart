import 'package:flutter/material.dart';

import '../../core/settings/homework_prefs.dart';

/// Переключатель группировки ДЗ: «задано в этот день» / «дедлайн».
/// Состояние общее через HomeworkPrefs, экраны синхронизируются сами.
class HomeworkGroupSwitcher extends StatelessWidget {
  const HomeworkGroupSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: HomeworkPrefs.groupByDue,
      builder: (context, groupByDue, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ещё немного — и кранты',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    groupByDue
                        ? 'Дедлайн — на выбранный день'
                        : 'Задано в выбранный день',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: groupByDue, onChanged: HomeworkPrefs.setGroupByDue),
          ],
        ),
      ),
    );
  }
}
