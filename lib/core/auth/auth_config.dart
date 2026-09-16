/// Переключатели авторизации.
///
/// Новый flow (device-token через ESIA) — основной. Старый PKCE + OAuth
/// refresh оставлен живым в коде: если флаг выключить, приложение вернётся
/// к прежнему поведению без отката. По умолчанию — новый flow.
class AuthConfig {
  AuthConfig._();

  /// true  — WebView на /authenticate/oauth?app=phone&…&sub_provider=esia,
  ///         обмен diaryperm://redirect?token=<UUID> на cookie-сессию.
  /// false — старый PKCE-флоу с auth-epos (см. _EposLoginView).
  static const useDeviceTokenFlow = true;

  /// Куда идти в WebView, чтобы начать интерактивный вход.
  /// device_key дописывается в конец в рантайме (см. DeviceTokenAuthService).
  static const deviceLoginStartPath = '/authenticate/oauth'
      '?app=phone'
      '&mode=epos'
      '&sub_provider=esia'
      '&device_key=';
}