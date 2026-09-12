import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/token_storage.dart';
import '../core/theme/theme_controller.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  final ThemeController themeController;

  const LoginScreen({super.key, required this.themeController});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  late final WebViewController _controller;
  String _status = 'Загрузка...';

  /// onPageFinished может выстрелить несколько раз подряд после логина
  /// (редиректы), поэтому уходим на HomeScreen строго один раз.
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = _authService.createLoginController(
      onStatus: (status) {
        if (mounted && !_navigated) setState(() => _status = status);
      },
      onTokensFound: (tokens) async {
        if (_navigated || !mounted) return;
        _navigated = true;

        // Сохраняем до навигации: если приложение убьют сразу после
        // логина — на следующем старте сразу попадём на Home.
        await TokenStorage().save(tokens);
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              tokens: tokens,
              themeController: widget.themeController,
            ),
          ),
        );
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