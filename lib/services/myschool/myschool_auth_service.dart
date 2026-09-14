import 'package:webview_flutter/webview_flutter.dart';

import 'myschool_tokens.dart';

/// Логин в «Мою школу» через Госуслуги.
class MySchoolAuthService {
  static const loginUrl = 'https://www.gosuslugi.ru/school/feed';
  static const targetDomain = 'gosuslugi.ru';

  WebViewController createLoginController({
    required void Function(MySchoolTokens tokens) onTokensFound,
    required void Function(String status) onStatus,
  }) {
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            onStatus('Страница: $url');
            if (!url.contains(targetDomain)) return;
            final tokens = await _tryExtract(controller);
            if (tokens != null) {
              onTokensFound(tokens);
            } else {
              onStatus('Куки пока не найдены — возможно, ещё не вошёл');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(loginUrl));
    return controller;
  }

  Future<MySchoolTokens?> _tryExtract(WebViewController controller) async {
    try {
      // document.cookie — строка вида "acc_t=…; u=…; studentId=…"
      final raw =
      await controller.runJavaScriptReturningResult('document.cookie');
      final cookieString =
      raw.toString().replaceAll(RegExp(r'^"|"$'), '');

      String? accT;
      String? u;
      String? sid;
      for (final pair in cookieString.split(';')) {
        final trimmed = pair.trim();
        final eq = trimmed.indexOf('=');
        if (eq < 0) continue;
        final name = trimmed.substring(0, eq);
        final value = trimmed.substring(eq + 1);
        if (name == 'acc_t') accT = value;
        if (name == 'u') u = value;
        if (name == 'studentId') sid = value;
      }
      if (accT == null || u == null || sid == null) return null;
      return MySchoolTokens(accT: accT, userId: u, studentId: sid);
    } catch (_) {
      return null;
    }
  }
}