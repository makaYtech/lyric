import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Иконка «Скопировать всё» с готовой логикой: сама решает, показываться
/// ли (пустой текст и «не задано» не копируем), сама кладёт в буфер и
/// показывает короткий snack.
///
/// Используется в модалках ДЗ — там, где рядом есть длинный текст,
/// который пользователю нужно скопировать целиком, а не выделять вручную.
class CopyAllButton extends StatelessWidget {
  /// Текст, который уйдёт в буфер. Если он пуст или равен «не задано»
  /// (в любом регистре, с любыми пробелами) — кнопка не отрисовывается.
  final String text;

  final String? tooltip;

  const CopyAllButton({super.key, required this.text, this.tooltip});

  bool get _hasSomethingToCopy {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t.toLowerCase() != 'не задано';
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSomethingToCopy) return const SizedBox.shrink();

    return IconButton(
      onPressed: () => _copy(context),
      icon: const Icon(Icons.copy_all_outlined, size: 20),
      tooltip: tooltip ?? 'Скопировать всё',
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Скопировано'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }
}
