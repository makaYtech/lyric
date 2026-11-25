/// Плотность отрисовки уроков. На телефоне и в узком окне — всегда
/// [comfortable]; в «дневнике» ScheduleView выбирает самую свободную,
/// при которой неделя помещается без прокрутки.
enum LessonDensity {
  /// Полная карточка: время, предмет, ДЗ, оценки (как на телефоне).
  comfortable(estRow: 124, estDayOverhead: 86),

  /// Две строки: время + предмет + оценки, ниже ДЗ.
  compact(estRow: 62, estDayOverhead: 56),

  /// Одна строка, как строчка в бумажном дневнике.
  dense(estRow: 38, estDayOverhead: 42);

  /// Оценка высоты одной строки расписания вместе с отступами (px).
  final double estRow;

  /// Оценка «накладных» на день: заголовок, паддинги, зазор (px).
  final double estDayOverhead;

  const LessonDensity({required this.estRow, required this.estDayOverhead});

  bool get isComfortable => this == LessonDensity.comfortable;
  bool get isDense => this == LessonDensity.dense;
}
