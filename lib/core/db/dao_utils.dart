import 'package:sqflite/sqflite.dart';

/// Последний `updated_at` в выборке [where]. null — если строк нет или
/// дата битая.
Future<DateTime?> lastUpdatedAt(
  Database db,
  String table, {
  required String where,
  required List<Object?> whereArgs,
}) async {
  final rows = await db.query(
    table,
    columns: const ['updated_at'],
    where: where,
    whereArgs: whereArgs,
    orderBy: 'updated_at DESC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return DateTime.tryParse(rows.first['updated_at'] as String);
}
