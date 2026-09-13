import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';
import 'backends.dart';

/// Выбранный источник данных. ValueNotifier — чтобы настройки и
/// потенциальные потребители (HomeScreen, LoginScreen) мгновенно
/// реагировали на смену без ручного перезапроса.
class BackendPrefs {
  BackendPrefs._();

  static const _key = 'active_backend';
  static final CacheService _cache = CacheService();

  static final ValueNotifier<String> current =
  ValueNotifier<String>(Backends.epos);

  static Future<void> load() async {
    final saved = await _cache.loadString(_key);
    if (saved != null && Backends.byId(saved).id == saved) {
      current.value = saved;
    } else {
      current.value = Backends.epos;
    }
  }

  static Future<void> set(String id) async {
    if (current.value == id) return;
    current.value = id;
    await _cache.saveString(_key, id);
  }
}