import 'package:flutter/material.dart';

import '../../core/theme/theme_controller.dart';
import '../../widgets/auth/device_auth_view.dart';
import '../home/home_screen.dart';

/// Первый вход по device-token flow: после успеха заменяет себя HomeScreen.
class DeviceLoginScreen extends StatelessWidget {
  final ThemeController themeController;

  const DeviceLoginScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return DeviceAuthView(
      deadMessage: 'Не удалось получить сессию. Попробуйте войти заново.',
      onSession: (ctx, session) => Navigator.of(ctx).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              HomeScreen(session: session, themeController: themeController),
        ),
      ),
    );
  }
}
