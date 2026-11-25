import 'package:flutter/material.dart';

/// Круглый значок с цветной обводкой и полупрозрачной заливкой — общая
/// геометрия для оценок и отметок об отсутствии.
class DotBase extends StatelessWidget {
  final Color color;
  final double size;
  final double borderWidth;
  final Widget child;
  final VoidCallback? onTap;

  const DotBase({
    super.key,
    required this.color,
    required this.size,
    required this.child,
    this.borderWidth = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: borderWidth),
      ),
      child: child,
    );

    if (onTap == null) return dot;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: dot,
    );
  }
}
