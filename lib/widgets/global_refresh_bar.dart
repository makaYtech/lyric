import 'package:flutter/material.dart';

/// Комбинированная кнопка обновления снизу экрана:
/// тап по основной части — обновляет данные на всех вкладках сразу;
/// стрелочка справа открывает меню с опцией "обновить только текущую".
class GlobalRefreshBar extends StatelessWidget {
  final DateTime? lastUpdated;
  final bool isLoading;
  final VoidCallback onRefreshAll;
  final VoidCallback onRefreshCurrent;
  final String currentTabLabel;

  const GlobalRefreshBar({
    super.key,
    required this.lastUpdated,
    required this.isLoading,
    required this.onRefreshAll,
    required this.onRefreshCurrent,
    required this.currentTabLabel,
  });

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                lastUpdated != null
                    ? 'Обновлено в ${_formatTime(lastUpdated!)}'
                    : 'Данные ещё не загружались',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: isLoading ? null : onRefreshAll,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLoading)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          else
                            Icon(Icons.refresh, size: 18, color: scheme.onPrimary),
                          const SizedBox(width: 6),
                          Text('Обновить', style: TextStyle(color: scheme.onPrimary)),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: scheme.onPrimary.withOpacity(0.3),
                  ),
                  PopupMenuButton<void>(
                    enabled: !isLoading,
                    tooltip: 'Варианты обновления',
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: onRefreshCurrent,
                        child: Text('Обновить только «$currentTabLabel»'),
                      ),
                    ],
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Icon(Icons.arrow_drop_down, color: scheme.onPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
