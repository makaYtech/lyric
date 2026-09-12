import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_service.dart';

/// Полноэкранный WebView для повторного входа.
/// Не пушит HomeScreen: после получения кук просто pop'ается с новыми
/// токенами — вызывающий код сам решит, что делать.
class ReauthScreen extends StatefulWidget {
  const ReauthScreen({super.key});

  @override
  State<ReauthScreen> createState() => _ReauthScreenState();
}

class _ReauthScreenState extends State<ReauthScreen> {
  final _authService = AuthService();
  late final WebViewController _controller;
  String _status = 'Загрузка...';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = _authService.createLoginController(
      onStatus: (s) {
        if (mounted && !_navigated) setState(() => _status = s);
      },
      onTokensFound: (tokens) {
        if (_navigated || !mounted) return;
        _navigated = true;
        Navigator.of(context).pop(tokens);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход в ЭПОС')),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _status,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}