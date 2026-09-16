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
/// Кэш двухуровневый:
///   1. in-memory `Map<String, String?>` — чтобы НЕ дёргать SharedPreferences
///      на каждый build виджета. Раньше ProfileView с 20 учителями делал
///      100+ async-чтений prefs при открытии вкладки.
///   2. SharedPreferences — источник правды между запусками.
///
/// Нотификация об изменениях — per-key. Раньше был один глобальный
/// ValueNotifier, и при смене одной аватарки перерисовывались ВСЕ
/// PersonAvatar в дереве. Теперь каждый аватар слушает только свой ключ.
class AvatarStorage {
  AvatarStorage._();
  static final _cache = CacheService();

  /// Кэш путей в памяти. null означает "не задано", отсутствие ключа —
  /// "ещё не читали из prefs". Различить через [isLoaded].
  static final Map<String, String?> _paths = {};
  static final Set<String> _loaded = {};

  /// Дедупликация параллельных чтений одного и того же ключа: два
  /// PersonAvatar с одинаковым avatarKey не должны читать prefs дважды.
  static final Map<String, Future<String?>> _inflight = {};

  /// Per-key нотифаеры. Создаются лениво при первом revisionFor(key).
  static final Map<String, ValueNotifier<int>> _keyRevisions = {};

  static String studentKey(String profileId) => 'avatar:student:$profileId';
  static String teacherKey(int teacherId) => 'avatar:teacher:$teacherId';

  /// Нотифаер для конкретного ключа. Подписка на него — единственный
  /// способ узнавать об изменении ЭТОЙ аватарки, не дёргая чужие.
  static ValueNotifier<int> revisionFor(String key) =>
      _keyRevisions.putIfAbsent(key, () => ValueNotifier<int>(0));

  /// Синхронный доступ к уже загруженному пути. Если ключ ещё не читали
  /// из prefs — вернёт null, но [isLoaded] при этом тоже false.
  static String? cachedPath(String key) => _paths[key];

  /// Уже читали ли этот ключ из prefs. Если false — [cachedPath] может
  /// врать (говорить null вместо реального пути).
  static bool isLoaded(String key) => _loaded.contains(key);

  /// Асинхронный доступ. При первом вызове читает из prefs и кэширует,
  /// при последующих — возвращает из памяти. Параллельные вызовы для
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
    return value;
  }

  static Future<void> savePath(String key, String? path) async {
    final value = (path == null || path.isEmpty) ? '' : path;
    await _cache.saveString(key, value);
    _paths[key] = value.isEmpty ? null : value;
    _loaded.add(key);
    revisionFor(key).value++;
  }

  static Future<void> clear(String key) async {
    await _cache.saveString(key, '');
    _paths[key] = null;
    _loaded.add(key);
    revisionFor(key).value++;
  }

  /// Массовая очистка: одна запись в prefs на ключ, но подписки
  /// нотифаеров дёргаются одним проходом. Используется в настройках,
  /// где сбрасываются аватарки всех учителей сразу.
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

  /// Полный сброс in-memory кэша. Нужен там, где prefs чистили в обход
  /// этого класса (logout, DeveloperScreen, fullWipe) — иначе в памяти
  /// останутся пути к файлам, ссылок на которые в prefs уже нет.
  /// Все подписчики получат нотификацию и перечитают из prefs (где пусто).
  static void invalidateAll() {
    _paths.clear();
    _loaded.clear();
    _inflight.clear();
    for (final n in _keyRevisions.values) {
      n.value++;
    }
  }
}