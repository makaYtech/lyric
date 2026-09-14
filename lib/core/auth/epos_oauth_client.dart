import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Чистый OAuth-клиент ЭПОСа. Никакого WebView, никакого UI.
///
/// Отвечает за:
///   - генерацию PKCE (verifier/challenge/state);
///   - построение URL для WebView;
///   - обмен authorization_code на access+refresh;
///   - refresh через grant_type=refresh_token.
///
/// Получение auth_token/profile_id делается вторым заходом в WebView
/// (см. login_screen) — там же, где ловим code.
class EposOAuthClient {
  static const _authBase = 'https://auth-epos.permkrai.ru';
  static const _realm = '/kk/auth/realms/epos';
  static const _clientId = 'auth';
  static const _redirectUri = '$_authBase/';

  static const _ua =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36';

  // ── PKCE ──────────────────────────────────────────────────────────

  static String generateVerifier() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String challengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static String generateState() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uri buildAuthUrl({
    required String challenge,
    required String state,
  }) =>
      Uri.parse('$_authBase$_realm/protocol/openid-connect/auth')
          .replace(queryParameters: {
        'response_type': 'code',
        'client_id': _clientId,
        'state': state,
        'scope': 'openid offline_access',
        'redirect_uri': _redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'response_mode': 'fragment',
      });

  // ── exchange & refresh ─────────────────────────────────────────────

  Future<TokenSet> exchangeCode({
    required String code,
    required String verifier,
    Map<String, String> cookies = const {},
  }) async {
    final body = await _postToken(
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'code': code,
        'code_verifier': verifier,
      },
      cookies: cookies,
    );
    return TokenSet.fromJson(body);
  }

  Future<TokenSet> refresh(String refreshToken) async {
    final body = await _postToken(
      body: {
        'grant_type': 'refresh_token',
        'client_id': _clientId,
        'refresh_token': refreshToken,
      },
      cookies: const {},
    );
    return TokenSet.fromJson(body);
  }

  Future<Map<String, dynamic>> _postToken({
    required Map<String, String> body,
    required Map<String, String> cookies,
  }) async {
    final client = HttpClient();
    client.userAgent = _ua;
    try {
      final req = await client.postUrl(
        Uri.parse('$_authBase$_realm/protocol/openid-connect/token'),
      );
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      req.headers.set('accept', '*/*');
      req.headers.set('origin', _authBase);
      req.headers.set('referer', '$_authBase/');
      req.followRedirects = false;
      for (final e in cookies.entries) {
        req.cookies.add(Cookie(e.key, e.value));
      }
      req.write(body.entries
          .map((e) =>
      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));

      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw EposOAuthException(
          'token endpoint вернул ${resp.statusCode}: $raw',
        );
      }
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}

class TokenSet {
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;

  const TokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  factory TokenSet.fromJson(Map<String, dynamic> json) {
    final expires = json['expires_in'] as int? ?? 900;
    return TokenSet(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt: DateTime.now().add(Duration(seconds: expires)),
    );
  }
}

class EposOAuthException implements Exception {
  final String message;
  const EposOAuthException(this.message);
  @override
  String toString() => 'EposOAuth: $message';
}