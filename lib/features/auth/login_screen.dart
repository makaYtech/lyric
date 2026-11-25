import 'package:flutter/material.dart';

import '../../core/auth/auth_config.dart';
import '../../core/theme/theme_controller.dart';
import '../../widgets/auth/pkce_auth_view.dart';
import './device_login_screen.dart';
import '../home/home_screen.dart';

/// Диспатчер входа: по AuthConfig.useDeviceTokenFlow.
///
/// ValueListenableBuilder нужен потому, что флаг меняется в рантайме из
/// DeveloperScreen. Если пользователь переключит flow и окажется на этом
/// экране — LoginScreen сам перерисуется на нужный.
class LoginScreen extends StatelessWidget {
  final ThemeController themeController;

  const LoginScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthConfig.useDeviceTokenFlow,
      builder: (context, useDevice, _) {
        if (useDevice) {
          return DeviceLoginScreen(themeController: themeController);
        }
        return PkceAuthView(
          onSession: (ctx, session) => Navigator.of(ctx).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomeScreen(
                session: session,
                themeController: themeController,
              ),
            ),
          ),
        );
      },
    );
  }
}
