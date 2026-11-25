import './epos_oauth_client.dart';
import './epos_session.dart';
import './epos_session_storage.dart';

/// Оркестратор жизненного цикла legacy-сессии: обновление access_token
/// по refresh_token. Device-token flow обслуживает AuthCoordinator напрямую.
class SessionRefreshService {
  SessionRefreshService._();
  static final instance = SessionRefreshService._();

  final _client = EposOAuthClient();
  final _storage = EposSessionStorage();

  Future<EposSession?>? _inFlight;

  Future<EposSession> ensureFresh(EposSession current) async {
    if (!current.needsRefresh) return current;
    final refreshed = await _refreshInternal(current);
    // Не удалось обновить (нет сети и т.п.) — не роняем сессию целиком:
    // auth_token отдельный и часто ещё жив, а офлайн-данные подтянутся
    // из локального кэша.
    return refreshed ?? current;
  }

  Future<EposSession?> forceRefresh(EposSession current) =>
      _refreshInternal(current);

  Future<EposSession?> _refreshInternal(EposSession current) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final fut = _doRefresh(current).whenComplete(() => _inFlight = null);
    _inFlight = fut;
    return fut;
  }

  Future<EposSession?> _doRefresh(EposSession current) async {
    // Device-token-сессия — сюда не ходит. Её refresh делает
    // AuthCoordinator::_renewViaDeviceToken.
    final rt = current.refreshToken;
    if (rt == null) return null;

    try {
      final fresh = await _client.refresh(rt);
      final updated = current.copyWith(
        accessToken: fresh.accessToken,
        refreshToken: fresh.refreshToken,
        accessExpiresAt: fresh.accessExpiresAt,
      );
      await _storage.save(updated);
      return updated;
    } catch (_) {
      return null;
    }
  }

  /// Собирает EposSession из уже полученных кусков (legacy PKCE-логин).
  ///
  /// cookies необязательны: для legacy-флоу ApiClient пойдёт по header-пути,
  /// а cookies подхватятся при первом renew.
  Future<EposSession> buildAndSave({
    required String code,
    required String verifier,
    required Map<String, String> authEposCookies,
    required String authToken,
    required String profileId,
    String? longToken,
    int? userId,
    Map<String, String> cookies = const {},
  }) async {
    final tokens = await _client.exchangeCode(
      code: code,
      verifier: verifier,
      cookies: authEposCookies,
    );
    final session = EposSession(
      authToken: authToken,
      profileId: profileId,
      cookies: cookies,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      accessExpiresAt: tokens.accessExpiresAt,
      longToken: longToken,
      userId: userId,
    );
    await _storage.save(session);
    return session;
  }

  Future<void> save(EposSession session) => _storage.save(session);
  Future<EposSession?> load() => _storage.load();
  Future<void> clear() => _storage.clear();
}
