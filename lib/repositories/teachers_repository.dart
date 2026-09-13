import '../core/db/teacher_dao.dart';
import '../models/teacher.dart';
import '../services/auth_service.dart';
import '../services/teachers_service.dart';

/// Учителя школы: реальный API + кэш в SQLite по годам.
class TeachersRepository {
  final TeachersService _service;
  final TeacherDao _dao;

  TeachersRepository({TeachersService? service, TeacherDao? dao})
      : _service = service ?? TeachersService(),
        _dao = dao ?? TeacherDao();

  Future<List<Teacher>?> loadCached(int yearId) async {
    final list = await _dao.loadAll(yearId);
    return list.isEmpty ? null : list;
  }

  Future<List<Teacher>> refresh(EposTokens tokens, int yearId) async {
    final list = await _service.fetchTeachers(tokens, academicYearId: yearId);
    await _dao.saveAll(yearId, list);
    return list;
  }

  Future<DateTime?> lastUpdated(int yearId) => _dao.lastUpdated(yearId);
}