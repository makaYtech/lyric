import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';

/// Персистентное хранилище токенов ЭПОСа.
/// После логина или re-auth кладём сюда пару authToken/profileId,
/// на старте приложения читаем — чтобы не показывать WebView, если
/// сессия ещё жива.
class TokenStorage {
  static const _authKey = 'epos_auth_token';
  static const _profileKey = 'epos_profile_id';

  Future<EposTokens?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final auth = prefs.getString(_authKey);
    final profile = prefs.getString(_profileKey);
    if (auth == null || profile == null) return null;
    return EposTokens(authToken: auth, profileId: profile);
  }

  Future<void> save(EposTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authKey, tokens.authToken);
    await prefs.setString(_profileKey, tokens.profileId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authKey);
    await prefs.remove(_profileKey);
  }
}