import 'package:flutter/material.dart';

/// Унифицированное отображение состояния "данных ещё нет / ошибка / контент".
/// Используется на всех экранах вместо самодельных if/else в build() —
/// так все экраны выглядят и ведут себя одинаково в этих трёх состояниях.
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
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (!hasData) {
      return Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : const Text('Нет данных. Нажми «Обновить».'),
      );
    }

    return contentBuilder(context);
  }
}
