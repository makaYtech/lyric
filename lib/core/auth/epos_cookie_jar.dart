import 'dart:io';

/// Простой cookie-jar для нескольких доменов.
/// Нужен для цепочки edu-epos → auth-epos → edu-epos:
/// сервер шлёт Set-Cookie на каждом шаге, и в следующий запрос
/// их надо вернуть. package:http этого не умеет — делаем вручную.
class EposCookieJar {
  final Map<String, Map<String, Cookie>> _byDomain = {};

  void addAll(Uri url, List<String> setCookieHeaders) {
    final domain = _normalizeDomain(url.host);
    final map = _byDomain.putIfAbsent(domain, () => {});
    for (final raw in setCookieHeaders) {
      final parsed = _parseSetCookie(raw);
      if (parsed == null) continue;
      map[parsed.name] = parsed;
    }
  }

  /// Все куки, применимые к url. Учитываем Path и Domain.
  List<Cookie> cookiesFor(Uri url) {
    final host = _normalizeDomain(url.host);
    final out = <Cookie>[];
    for (final entry in _byDomain.entries) {
      if (!_domainMatches(entry.key, host)) continue;
      for (final c in entry.value.values) {
        if (!_pathMatches(c.path ?? '/', url.path)) continue;
        out.add(c);
      }
    }
    return out;
  }

  Map<String, String> asMap() => {
    for (final e in _byDomain.entries)
      for (final c in e.value.values) c.name: c.value,
  };

  static String _normalizeDomain(String host) =>
      host.startsWith('www.') ? host.substring(4) : host;

  static bool _domainMatches(String cookieDomain, String host) =>
      host == cookieDomain || host.endsWith('.$cookieDomain');

  static bool _pathMatches(String cookiePath, String urlPath) {
    if (cookiePath == '/' || cookiePath.isEmpty) return true;
    return urlPath.startsWith(cookiePath);
  }

  Cookie? _parseSetCookie(String raw) {
    final parts = raw.split(';');
    if (parts.isEmpty) return null;
    final first = parts.first;
    final eq = first.indexOf('=');
    if (eq < 0) return null;
    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (name.isEmpty) return null;
    final cookie = Cookie(name, value);
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      final lo = p.toLowerCase();
      if (lo.startsWith('path=')) cookie.path = p.substring(5);
      // Domain не используем — полагаемся на host из URL запроса.
    }
    return cookie;
  }
}