import 'package:flutter/material.dart';

/// Унифицированное отображение состояния "данных ещё нет / ошибка / контент".
/// Используется на всех экранах вместо самодельных if/else в build() —
/// так все экраны выглядят и ведут себя одинаково в этих трёх состояниях.
///
/// Состояния «ошибка» и «нет данных» рендерятся в скроллируемом контейнере,
/// чтобы работал pull-to-refresh, даже когда показывать нечего.
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
      return const _FillScrollable(
        child: Text('Нет данных. Потяни вниз, чтобы обновить.'),
      );
    }

    return contentBuilder(context);
  }
}

/// Однокадровый скроллируемый контейнер высотой с родителя, внутри —
/// центр с [child]. Нужен, чтобы RefreshIndicator мог поймать
/// pull-to-refresh даже на экране, где нечего показывать.
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}