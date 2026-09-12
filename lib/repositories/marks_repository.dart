import '../core/db/marks_dao.dart';
import '../models/mark.dart';
import '../services/auth_service.dart';
import '../services/marks_service.dart';

/// Обёртка над MarksService: сохраняет marks за неделю в SQLite.
/// Расписание использует marks для точек, и оффлайн они должны
/// подтягиваться из БД — той же неделей, что и уроки.
class MarksRepository {
  final MarksService _service;
  final MarksDao _dao;

  MarksRepository({MarksService? service, MarksDao? dao})
      : _service = service ?? MarksService(),
        _dao = dao ?? MarksDao();

  Future<List<Mark>> refresh(
      EposTokens tokens,
      int yearId, {
        required DateTime from,
        required DateTime to,
      }) async {
    final marks = await _service.fetchMarks(tokens, from: from, to: to);
    await _dao.saveWeek(yearId, _mondayOf(from), marks);
    return marks;
  }

  Future<List<Mark>> loadCached(int yearId, DateTime monday) =>
      _dao.loadWeek(yearId, monday);

  Future<DateTime?> lastUpdated(int yearId, DateTime monday) =>
      _dao.lastUpdated(yearId, monday);

  DateTime _mondayOf(DateTime d) {
    final m = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(m.year, m.month, m.day);
  }
}