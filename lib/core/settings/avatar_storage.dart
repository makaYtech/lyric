import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Хранит ТОЛЬКО путь к картинке на устройстве. Сам файл никуда не
/// копируется и не кэшируется — при каждой отрисовке аватар читается
/// с диска. Если файл удалили/переместили — упадёт фоллбэк на инициалы.
///
/// Ключ — произвольная строка, уникальная для персоны:
///   student:<profileId>
///   teacher:<teacherId>
///
/// [revision] — глобальный счётчик изменений. Инкрементируется при
/// каждом savePath/clear. PersonAvatar на него подписан и перечитывает
/// путь с диска. Это позволяет, например, сбросить аватар в настройках
/// и увидеть изменения на вкладке Профиль без перезахода на неё.
class AvatarStorage {
  AvatarStorage._();
  static final _cache = CacheService();

  /// Инкрементируется при любом изменении любого пути.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static String studentKey(String profileId) => 'avatar:student:$profileId';
  static String teacherKey(int teacherId) => 'avatar:teacher:$teacherId';

  static Future<String?> path(String key) => _cache.loadString(key);

  static Future<void> savePath(String key, String? path) async {
    // null или пустая строка = "убрать картинку"
    if (path == null || path.isEmpty) {
      await _cache.saveString(key, '');
    } else {
      await _cache.saveString(key, path);
    }
    revision.value++;
  }

  static Future<void> clear(String key) async {
    await _cache.saveString(key, '');
    revision.value++;
  }
}