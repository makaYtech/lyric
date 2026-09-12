import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ВАЖНО: замени `epos_app` на имя своего пакета из pubspec.yaml.
import 'package:epos_clien/widgets/common/grade_dot.dart';

void main() {
  group('gradeColor', () {
    test('пятёрка — зелёная', () {
      expect(gradeColor(5), Colors.green);
    });

    test('четвёрка — синяя', () {
      expect(gradeColor(4), Colors.blue);
    });

    test('тройка — оранжевая', () {
      expect(gradeColor(3), Colors.orange);
    });

    test('двойка — красная', () {
      expect(gradeColor(2), Colors.red);
    });

    test('неизвестное значение — серая', () {
      expect(gradeColor(1), Colors.grey);
      expect(gradeColor(0), Colors.grey);
    });
  });
}