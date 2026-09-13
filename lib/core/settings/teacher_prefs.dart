import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Настройки отображения карточки учителя в профиле.
///
/// Лимиты «сколько показывать до кнопки "Ещё N"» можно менять в
/// настройках (Профиль → Учителя). Значение [allValue] (-1) означает
/// «показать всё без ограничения».
///
/// ValueNotifier — чтобы карточки учителей сразу перерисовывались при
/// изменении настроек, без перезахода на вкладку.
class TeacherPrefs {
  TeacherPrefs._();

  static const allValue = -1;

  static const defaultSubjectsLimit = 5;
  static const defaultRoomsLimit = 5;

  static const _subjectsKey = 'teacher_subjects_limit';
  static const _roomsKey = 'teacher_rooms_limit';
  static const _oldRoomsKey = 'teacher_show_old_rooms';
  static const _onlyStudentTeachersKey = 'teacher_only_student_teachers';

  static final CacheService _cache = CacheService();

  static final ValueNotifier<int> subjectsLimit =
  ValueNotifier<int>(defaultSubjectsLimit);

  static final ValueNotifier<int> roomsLimit =
  ValueNotifier<int>(defaultRoomsLimit);

  /// Показывать все исторические кабинеты учителя, а не только те,
  /// где он ответственный. По умолчанию — выключено: у ЭПОСа в
  /// teacher_profiles.rooms[] лежит мусорный хвост за много лет.
  static final ValueNotifier<bool> showOldRooms =
  ValueNotifier<bool>(false);

  /// Показывать только учителей, которые ведут уроки у текущего
  /// ученика. Список id строится контроллером из расписания.
  static final ValueNotifier<bool> onlyStudentTeachers =
  ValueNotifier<bool>(false);

  static Future<void> load() async {
    final s = await _cache.loadInt(_subjectsKey);
    final r = await _cache.loadInt(_roomsKey);
    final o = await _cache.loadInt(_oldRoomsKey);
    final os = await _cache.loadInt(_onlyStudentTeachersKey);
    subjectsLimit.value = s ?? defaultSubjectsLimit;
    roomsLimit.value = r ?? defaultRoomsLimit;
    showOldRooms.value = (o ?? 0) == 1;
    onlyStudentTeachers.value = (os ?? 0) == 1;
  }

  static Future<void> setSubjectsLimit(int value) async {
    subjectsLimit.value = value;
    await _cache.saveInt(_subjectsKey, value);
  }

  static Future<void> setRoomsLimit(int value) async {
    roomsLimit.value = value;
    await _cache.saveInt(_roomsKey, value);
  }

  static Future<void> setShowOldRooms(bool value) async {
    showOldRooms.value = value;
    await _cache.saveInt(_oldRoomsKey, value ? 1 : 0);
  }

  static Future<void> setOnlyStudentTeachers(bool value) async {
    onlyStudentTeachers.value = value;
    await _cache.saveInt(_onlyStudentTeachersKey, value ? 1 : 0);
  }

  /// «5» / «Все» — для подписи в настройках.
  static String limitLabel(int value) =>
      value == allValue ? 'Показать всё' : '$value';
}