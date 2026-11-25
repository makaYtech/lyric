import '../../core/db/marks_dao.dart';
import '../../core/util/date_time.dart';
import '../../domain/grades/mark.dart';
import '../services/epos/auth_service.dart';
import '../services/epos/marks_service.dart';

/// Обёртка над MarksService: сохраняет marks за неделю в SQLite, чтобы
/// расписание могло показать их оффлайн.
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
    await _dao.saveWeek(yearId, mondayOf(from), marks);
    return marks;
  }

  Future<List<Mark>> loadCached(int yearId, DateTime monday) =>
      _dao.loadWeek(yearId, monday);

  Future<DateTime?> lastUpdated(int yearId, DateTime monday) =>
      _dao.lastUpdated(yearId, monday);
}
