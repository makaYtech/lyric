import '../core/db/homework_dao.dart';
import '../models/homework.dart';
import '../services/auth_service.dart';
import '../services/homework_service.dart';

class HomeworkRepository {
  final HomeworkService _service;
  final HomeworkDao _dao;

  HomeworkRepository({HomeworkService? service, HomeworkDao? dao})
      : _service = service ?? HomeworkService(),
        _dao = dao ?? HomeworkDao();

  Future<List<Homework>?> loadCached(int yearId) async {
    final list = await _dao.loadAll(yearId);
    return list.isEmpty ? null : list;
  }

  Future<List<Homework>> refresh(
      EposTokens tokens,
      int yearId, {
        required DateTime from,
        required DateTime to,
      }) async {
    final list = await _service.fetchHomeworks(
      tokens,
      from: from,
      to: to,
      academicYearId: yearId,
    );
    await _dao.saveAll(yearId, list);
    return list;
  }

  Future<DateTime?> lastUpdated(int yearId) => _dao.lastUpdated(yearId);
}