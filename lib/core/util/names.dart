import 'package:characters/characters.dart';

/// Работа с ФИО. Два близких, но разных сценария:
/// - shortTeacherName — "Кривошеева Т. А." для плотных списков уроков;
/// - initials — "КТ" / "И" для аватара в профиле.

/// "Иванов Иван Валентинович" → "Иванов И. В."
/// "ИВАНОВА мария сергеевна" → "Иванова М. С."
/// Фамилия всегда приводится к формату "Первая заглавная, остальные
/// строчные" — с ЭПОСа она иногда прилетает капсом или как попало.
/// Одну фамилию не трогаем.
String shortTeacherName(String full) {
  final parts = full
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return full;
  final last = capitalizeFirst(parts.first);
  if (parts.length < 2) return last;
  final initialsPart = parts
      .skip(1)
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}.')
      .join(' ');
  return '$last $initialsPart';
}

/// "БАТАКОВА ЕВГЕНИЯ ЛЕОНИДОВНА" → "Батакова Евгения Леонидовна"
/// "Иванова Мария Сергеевна" → без изменений
/// Нормализует регистр всех слов — нужно для полного ФИО в карточках.
String normalizeFullName(String full) {
  return full
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .map(capitalizeFirst)
      .join(' ');
}

/// "Иванов Иван Иванович" → "ИИ"
String initials(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return (parts.first.characters.first + parts[1].characters.first)
      .toUpperCase();
}

/// Первая буква заглавная, остальные строчные. Публичная — используется
/// и в коротком ФИО, и в названиях кабинетов.
String capitalizeFirst(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}