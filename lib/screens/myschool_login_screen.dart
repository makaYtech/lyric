import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/myschool_token_storage.dart';
import '../core/theme/theme_controller.dart';
import '../services/myschool/myschool_auth_service.dart';
import 'myschool_home_screen.dart';

class MySchoolLoginScreen extends StatefulWidget {
  final ThemeController themeController;
  const MySchoolLoginScreen({super.key, required this.themeController});

  @override
  State<MySchoolLoginScreen> createState() => _MySchoolLoginScreenState();
}

class _MySchoolLoginScreenState extends State<MySchoolLoginScreen> {
  final _auth = MySchoolAuthService();
  late final WebViewController _controller;
  String _status = 'Загрузка...';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = _auth.createLoginController(
      onStatus: (s) {
        if (mounted && !_navigated) setState(() => _status = s);
      },
      onTokensFound: (tokens) async {
        if (_navigated || !mounted) return;
        _navigated = true;
        await MySchoolTokenStorage().save(tokens);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MySchoolHomeScreen(
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
      appBar: AppBar(title: const Text('Вход в Мою школу')),
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