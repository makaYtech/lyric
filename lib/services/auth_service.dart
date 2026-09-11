import 'package:webview_flutter/webview_flutter.dart';

/// То немногое, что нужно всем остальным сервисам для похода в API ЭПОСа.
class EposTokens {
  final String authToken;
  final String profileId;

  EposTokens({required this.authToken, required this.profileId});
}

class AuthService {
  static const loginUrl = 'https://edu-epos.permkrai.ru/';
  static const targetDomain = 'edu-epos.permkrai.ru';

  /// Создаёт WebViewController, настроенный на логин ЭПОСа.
  /// [onTokensFound] вызовется, как только куки auth_token/profile_id
  /// появятся после успешного входа. [onStatus] — для отладочного вывода.
  WebViewController createLoginController({
    required void Function(EposTokens tokens) onTokensFound,
    required void Function(String status) onStatus,
  }) {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            onStatus('Страница загружена: $url');
            if (!url.contains(targetDomain)) return;

            final tokens = await _tryExtractTokens(controller);
            if (tokens != null) {
              onTokensFound(tokens);
            } else {
              onStatus('Куки получены, но auth_token/profile_id не найдены');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(loginUrl));
    return controller;
  }

  Future<EposTokens?> _tryExtractTokens(WebViewController controller) async {
    final rawResult = await controller.runJavaScriptReturningResult(
      'document.cookie',
    );
    final rawCookies = rawResult.toString().replaceAll(RegExp(r'^"|"$'), '');

    String? authToken;
    String? profileId;

    for (final pair in rawCookies.split(';')) {
      final parts = pair.trim().split('=');
      if (parts.length != 2) continue;
      if (parts[0] == 'auth_token') authToken = parts[1];
      if (parts[0] == 'profile_id') profileId = parts[1];
    }

    if (authToken == null || profileId == null) return null;
    return EposTokens(authToken: authToken, profileId: profileId);
  }
}
