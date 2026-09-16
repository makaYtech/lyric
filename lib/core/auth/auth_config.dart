import 'package:flutter/foundation.dart';

import '../cache/cache_service.dart';

/// Переключатели авторизации.
///
/// useDeviceTokenFlow — главный флаг. Хранится в SharedPreferences,
/// меняется из DeveloperScreen. По умолчанию — новый flow.
///
///   true  — WebView на /authenticate/oauth?app=phone&…&sub_provider=esia,
///           обмен diaryperm://redirect?token=<UUID> на cookie-сессию.
///           Refresh — один GET /authenticate с заголовком token.
///   false — legacy PKCE-флоу с auth-epos: /token?grant_type=refresh_token,
///           потом Phase C через скрытый WebView. Оставлен на случай,
///           если device-token-flow сломается на стороне сервера и
///           пользователю понадобится зайти другим способом.
///
/// Флаг применяется при СЛЕДУЮЩЕМ логине. Текущая сессия продолжает
/// работать тем flow, которым была получена: в EposSession лежит либо
/// deviceToken (новый flow), либо OAuth-пара (legacy), и AuthCoordinator
/// роутит refresh по этим полям, а не по флагу. Поэтому переключение
/// флага во время работы не ломает текущую сессию — оно влияет только
/// на то, какой экран откроется, когда пользователь выйдет и зайдёт
/// заново.
class AuthConfig {
  AuthConfig._();

  static const _prefKey = 'auth_use_device_token_flow';
  static final CacheService _cache = CacheService();

  static final ValueNotifier<bool> useDeviceTokenFlow =
  ValueNotifier<bool>(true);

  static Future<void> load() async {
    final saved = await _cache.loadInt(_prefKey);
    useDeviceTokenFlow.value = saved == null ? true : saved == 1;
  }

  static Future<void> setUseDeviceTokenFlow(bool value) async {
    if (useDeviceTokenFlow.value == value) return;
    useDeviceTokenFlow.value = value;
    await _cache.saveInt(_prefKey, value ? 1 : 0);
  }

  /// Куда идти в WebView, чтобы начать интерактивный вход.
  /// device_key дописывается в конец в рантайме (см. DeviceTokenAuthService).
  static const deviceLoginStartPath = '/authenticate/oauth'
      '?app=phone'
      '&mode=epos'
      '&sub_provider=esia'
      '&device_key=';
}