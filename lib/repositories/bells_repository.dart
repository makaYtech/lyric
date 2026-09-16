import 'dart:convert';

import '../core/db/bells_dao.dart';
import '../models/bells_timetable.dart';
import '../services/auth_service.dart';
import '../services/bells_service.dart';

/// Кэш расписания звонков: read-through.
class BellsRepository {
  final BellsService _service;
  final BellsDao _dao;

  BellsRepository({BellsService? service, BellsDao? dao})
      : _service = service ?? BellsService(),
        _dao = dao ?? BellsDao();

  Future<BellsTimetable?> loadCached(int yearId) async {
    final raw = await _dao.loadRaw(yearId);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return BellsTimetable.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<BellsTimetable> refresh(
      EposTokens tokens, {
        required int timetableId,
        required int academicYearId,
      }) async {
    final result = await _service.fetch(
      tokens,
      timetableId: timetableId,
      academicYearId: academicYearId,
    );
    await _dao.save(academicYearId, result.id, result.rawJson);
    return result.model;
  }

  Future<DateTime?> lastUpdated(int yearId) => _dao.lastUpdated(yearId);
  Future<void> clearYear(int yearId) => _dao.clearYear(yearId);
}