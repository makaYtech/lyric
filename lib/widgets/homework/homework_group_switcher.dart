import 'package:flutter/material.dart';

import '../../core/settings/homework_prefs.dart';

/// Переключатель режима группировки ДЗ: «Задано в этот день» vs
/// «Дедлайн — на этот день». Используется и на вкладке ДЗ, и на
/// вкладке расписания — состояние общее через HomeworkPrefs.
///
/// Виджет самодостаточный: слушает ValueNotifier и сам же его меняет.
/// Наружу ничего прокидывать не надо — оба экрана автоматически
/// синхронизируются через общий нотифаер.
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
