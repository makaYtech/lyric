/// Типизированные чтения из JSON-объектов ЭПОСа.
///
/// Касты сохраняют прежнюю строгость: неверный тип по-прежнему бросает
/// TypeError, а не подменяется дефолтом.
extension JsonMap on Map<String, dynamic> {
  String str(String key) => this[key] as String? ?? '';

  String strOr(String key, String fallback) => this[key] as String? ?? fallback;

  int intOr(String key, int fallback) => this[key] as int? ?? fallback;

  int? intOrNull(String key) => this[key] as int?;

  /// Число или числовая строка; иначе null.
  double? doubleOrNull(String key) {
    final value = this[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool boolOr(String key, [bool fallback = false]) =>
      this[key] as bool? ?? fallback;

  List<dynamic> list(String key) => this[key] as List<dynamic>? ?? const [];

  List<Map<String, dynamic>> mapList(String key) =>
      list(key).whereType<Map<String, dynamic>>().toList();
}
