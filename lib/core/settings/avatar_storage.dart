import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Хранит только путь к картинке на устройстве; сам файл не копируется.
/// Ключи: `student:<profileId>`, `teacher:<teacherId>`.
///
/// Кэш двухуровневый: in-memory (чтобы не дёргать prefs на каждый build)
/// и SharedPreferences (источник правды между запусками). Нотификация —
/// per-key, чтобы смена одной аватарки не перерисовывала все PersonAvatar.
class AvatarStorage {
  AvatarStorage._();
  static final _cache = CacheService();

  /// null — «не задано», отсутствие ключа — «ещё не читали из prefs».
  static final Map<String, String?> _paths = {};
  static final Set<String> _loaded = {};

  /// Дедупликация параллельных чтений одного ключа.
  static final Map<String, Future<String?>> _inflight = {};

  static final Map<String, ValueNotifier<int>> _keyRevisions = {};

  static String studentKey(String profileId) => 'avatar:student:$profileId';
  static String teacherKey(int teacherId) => 'avatar:teacher:$teacherId';

  /// Нотифаер конкретного ключа; подписка на него не задевает чужие аватары.
  static ValueNotifier<int> revisionFor(String key) =>
      _keyRevisions.putIfAbsent(key, () => ValueNotifier<int>(0));

  /// Синхронный доступ к уже загруженному пути.
  static String? cachedPath(String key) => _paths[key];

  /// Читали ли ключ из prefs. Если false — [cachedPath] может врать.
  static bool isLoaded(String key) => _loaded.contains(key);

  /// При первом вызове читает из prefs и кэширует; параллельные вызовы
  /// одного ключа схлопываются в одно чтение.
  static Future<String?> path(String key) {
    if (_loaded.contains(key)) return Future.value(_paths[key]);
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final fut = _readFromPrefs(key).whenComplete(() => _inflight.remove(key));
    _inflight[key] = fut;
    return fut;
  }

  static Future<String?> _readFromPrefs(String key) async {
    final raw = await _cache.loadString(key);
    final value = (raw == null || raw.isEmpty) ? null : raw;
    _paths[key] = value;
    _loaded.add(key);
    // Без уведомления PersonAvatar застревал с инициалами до пересоздания.
    revisionFor(key).value++;
    return value;
  }

  /// Сохраняет путь как есть, без копирования файла: при выборе новой
  /// картинки путь меняется, и `Image.file` не подсунет старый кэш.
  static Future<void> savePath(String key, String? path) async {
    if (path == null || path.isEmpty) {
      await clear(key);
      return;
    }
    await _cache.saveString(key, path);
    _paths[key] = path;
    _loaded.add(key);
    revisionFor(key).value++;
  }

  static Future<void> clear(String key) async {
    await _cache.saveString(key, '');
    _paths[key] = null;
    _loaded.add(key);
    revisionFor(key).value++;
  }

  /// Массовая очистка с одним проходом по нотифаерам.
  static Future<void> clearAll(Iterable<String> keys) async {
    for (final key in keys) {
      await _cache.saveString(key, '');
      _paths[key] = null;
      _loaded.add(key);
    }
    for (final key in keys) {
      revisionFor(key).value++;
    }
  }

  /// Сброс in-memory кэша, если prefs чистили в обход этого класса
  /// (logout, DeveloperScreen, fullWipe). Подписчики перечитают из prefs.
  static void invalidateAll() {
    _paths.clear();
    _loaded.clear();
    _inflight.clear();
    for (final n in _keyRevisions.values) {
      n.value++;
    }
  }
}
