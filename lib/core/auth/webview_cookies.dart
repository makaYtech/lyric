import 'package:webview_flutter/webview_flutter.dart';

/// `document.cookie` из WebView в виде карты.
///
/// HttpOnly-куки сюда не попадают — для /token-запроса Keycloak
/// принимает заголовки как основной канал, поэтому этого достаточно.
Future<Map<String, String>> readDocumentCookies(
  WebViewController controller,
) async {
  try {
    final raw = await controller.runJavaScriptReturningResult(
      'document.cookie',
    );
    final str = raw.toString().replaceAll(RegExp(r'^"|"$'), '');
    final out = <String, String>{};
    for (final pair in str.split('; ')) {
      final i = pair.indexOf('=');
      if (i > 0) out[pair.substring(0, i)] = pair.substring(i + 1);
    }
    return out;
  } catch (_) {
    return <String, String>{};
  }
}
