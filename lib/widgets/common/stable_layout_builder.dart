import 'package:flutter/widgets.dart';

/// Как [LayoutBuilder], но дерево ниже пересобирается ТОЛЬКО когда меняется
/// «ключ раскладки» [keyOf] (например, широкий/узкий режим или число колонок),
/// а не на каждом пикселе ресайза.
///
/// Зачем: обычный LayoutBuilder вызывает builder на каждый кадр при
/// растягивании окна, и всё, что внутри (карточки расписания, оценки, колонки
/// ДЗ), создаётся заново. Здесь на неизменный ключ возвращается ТОТ ЖЕ
/// виджет — Flutter не пересобирает его, остаётся только дешёвый relayout.
///
/// Правила:
///  * [keyOf] должен возвращать дискретное значение (bool, int, enum, record),
///    которое сравнивается по `==`;
///  * [builder] не должен использовать «сырые» размеры из constraints — только
///    то, что вошло в ключ, иначе при ресайзе они устареют;
///  * кэш сбрасывается, когда родитель пересобрал сам StableLayoutBuilder
///    (то есть при любом изменении данных/состояния родителя).
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
    // Родитель пересобрался (данные/состояние могли измениться) — кэш не
    // годится.
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
