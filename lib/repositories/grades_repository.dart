import '../core/db/grades_dao.dart';
import '../models/grade_slice.dart';
import '../models/subject_grade.dart';
import '../services/auth_service.dart';
import '../services/grades_service.dart';

class GradesRepository {
  final GradesService _service;
  final GradesDao _dao;

  GradesRepository({GradesService? service, GradesDao? dao})
      : _service = service ?? GradesService(),
        _dao = dao ?? GradesDao();

  Future<List<SubjectGrade>?> loadCached(int yearId) async {
    final slices = await _dao.loadCurrent(yearId);
    if (slices.isEmpty) return null;
    return _toSubjectGrades(slices);
  }

  Future<List<SubjectGrade>> refresh(EposTokens tokens, int yearId) async {
    final grades = await _service.fetchGrades(tokens, academicYearId: yearId);
    await _dao.sync(yearId, grades);
    return grades;
  }

  Future<DateTime?> lastUpdated(int yearId) => _dao.lastUpdated(yearId);

  Future<List<GradeSlice>> changedSince(int yearId) async {
    final slices = await _dao.loadCurrent(yearId);
    return slices.where((s) => s.changed).toList();
  }

  Future<List<GradeHistoryEntry>> historyFor(
      int yearId,
      String subject,
      String period,
      String workType,
      ) =>
      _dao.historyFor(yearId, subject, period, workType);

  Future<void> acknowledgeChange(
      int yearId,
      String subject,
      String period,
      String workType,
      ) =>
      _dao.acknowledge(yearId, subject, period, workType);

  List<SubjectGrade> _toSubjectGrades(List<GradeSlice> slices) {
    final bySubject = <String, Map<String, List<GradeSlice>>>{};
    for (final s in slices) {
      bySubject.putIfAbsent(s.subject, () => {});
      bySubject[s.subject]!.putIfAbsent(s.period, () => []).add(s);
    }

    return bySubject.entries.map((subjectEntry) {
      final periods = subjectEntry.value.entries.map((periodEntry) {
        final workTypes = periodEntry.value
            .map((s) => WorkTypeGrades(
          workType: s.workType,
          grades: s.grades,
          dates: s.dates,
          comments: s.comments,
        ))
            .toList();
        return PeriodGrades(name: periodEntry.key, workTypes: workTypes);
      }).toList();
      return SubjectGrade(name: subjectEntry.key, periods: periods);
    }).toList();
  }
}