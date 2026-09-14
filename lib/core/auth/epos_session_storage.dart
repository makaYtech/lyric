import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'epos_session.dart';

/// Хранит EposSession в системном keychain/keystore.
/// Refresh_token — очень чувствительный, SharedPreferences не годится.
class EposSessionStorage {
  static const _key = 'epos_session_v1';
  final FlutterSecureStorage _storage;

  EposSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
      const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  Future<EposSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return EposSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      await _storage.delete(key: _key);
      return null;
    }
  }

  Future<void> save(EposSession session) async {
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}