import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Канал обновлений: приложение смотрит только выбранный канал в
/// update.json. Канал — имя ключа в файле; нет записи — нет предложения.
enum UpdateChannel { release, beta }

class UpdatePrefs {
  UpdatePrefs._();

  static const _channelKey = 'update_channel';

  static final CacheService _cache = CacheService();

  static final ValueNotifier<UpdateChannel> channel =
      ValueNotifier<UpdateChannel>(UpdateChannel.release);

  static Future<void> load() async {
    final raw = await _cache.loadString(_channelKey);
    channel.value = _parse(raw);
  }

  static Future<void> setChannel(UpdateChannel value) async {
    if (channel.value == value) return;
    channel.value = value;
    await _cache.saveString(_channelKey, value.name);
  }

  static UpdateChannel _parse(String? raw) {
    if (raw == null) return UpdateChannel.release;
    return UpdateChannel.values.firstWhere(
      (c) => c.name == raw,
      orElse: () => UpdateChannel.release,
    );
  }
}
