import 'package:flutter/material.dart';

import '../../core/layout/adaptive.dart';

/// Унифицированное состояние «нет данных / ошибка / контент». Ошибка и
/// пустота рендерятся в скролле, чтобы работал pull-to-refresh.
class AsyncStateView extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final bool hasData;
  final WidgetBuilder contentBuilder;

  const AsyncStateView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.hasData,
    required this.contentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return _FillScrollable(
        child: Text(
          error!,
          style: TextStyle(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (!hasData) {
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _FillScrollable(
        child: Text(
          AdaptiveLayout.isDesktopOS
              ? 'Нет данных. Нажмите F5, чтобы обновить.'
              : 'Нет данных. Потяни вниз, чтобы обновить.',
        ),
      );
    }

    return contentBuilder(context);
  }
}

/// Скроллируемый контейнер высотой с родителя — чтобы RefreshIndicator
/// ловил pull-to-refresh даже на пустом экране.
class _FillScrollable extends StatelessWidget {
  final Widget child;
  const _FillScrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        );
      },
    );
  }
}
