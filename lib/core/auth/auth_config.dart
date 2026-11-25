import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Переключатель флоу авторизации.
///
/// true — device-token flow (WebView → diaryperm://redirect → трёхшаговый
/// exchange), false — legacy PKCE. Флаг применяется при следующем логине:
/// текущая сессия обновляется тем flow, которым была получена (см.
/// EposSession.deviceToken), а не по этому флагу.
class AuthConfig {
  AuthConfig._();

  static const _prefKey = 'auth_use_device_token_flow';
  static final CacheService _cache = CacheService();

  static final ValueNotifier<bool> useDeviceTokenFlow = ValueNotifier<bool>(
    true,
  );

  static Future<void> load() async {
    final saved = await _cache.loadInt(_prefKey);
    useDeviceTokenFlow.value = saved == null ? true : saved == 1;
  }

  static Future<void> setUseDeviceTokenFlow(bool value) async {
    if (useDeviceTokenFlow.value == value) return;
    useDeviceTokenFlow.value = value;
    await _cache.saveInt(_prefKey, value ? 1 : 0);
  }

  /// Стартовый URL интерактивного входа. device_key в дампе оригинала
  /// отсутствует — не шлём.
  static const deviceLoginStartPath =
      '/authenticate/oauth'
      '?app=phone'
      '&mode=epos'
      '&sub_provider=esia';
}
