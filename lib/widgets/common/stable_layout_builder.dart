import 'package:flutter/widgets.dart';

/// Как [LayoutBuilder], но дерево ниже пересобирается только при смене
/// ключа раскладки [keyOf], а не на каждом пикселе ресайза: на неизменный
/// ключ возвращается тот же виджет, и Flutter делает лишь дешёвый relayout.
///
/// [keyOf] должен возвращать дискретное значение (bool, int, enum, record),
/// а [builder] — не использовать «сырые» размеры из constraints. Кэш
/// сбрасывается, когда родитель пересобрал сам StableLayoutBuilder.
class StableLayoutBuilder<K> extends StatefulWidget {
  final K Function(BoxConstraints constraints) keyOf;
  final Widget Function(BuildContext context, BoxConstraints constraints, K key)
  builder;

  const StableLayoutBuilder({
    super.key,
    required this.keyOf,
    required this.builder,
  });

  @override
  State<StableLayoutBuilder<K>> createState() => _StableLayoutBuilderState<K>();
}

class _StableLayoutBuilderState<K> extends State<StableLayoutBuilder<K>> {
  K? _key;
  Widget? _child;

  @override
  void didUpdateWidget(StableLayoutBuilder<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Родитель пересобрался — данные могли измениться, кэш не годится.
    _child = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final key = widget.keyOf(constraints);
        if (_child == null || key != _key) {
          _key = key;
          _child = widget.builder(context, constraints, key);
        }
        return _child!;
      },
    );
  }
}
