import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'core/auth/token_storage.dart';
import 'core/theme/theme_controller.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.load();
  // Токены могли остаться с прошлого запуска. Если есть — сразу Home,
  // никакого WebView: если сервер скажет «сессия истекла», SessionNotifier
  // сам выкатит модалку с re-auth.
  final initialTokens = await TokenStorage().load();
  runApp(EposApp(
    themeController: themeController,
    initialTokens: initialTokens,
  ));
}

class EposApp extends StatelessWidget {
  final ThemeController themeController;
  final EposTokens? initialTokens;

  const EposApp({
    super.key,
    required this.themeController,
    required this.initialTokens,
  });

  @override
  Widget build(BuildContext context) {
    // DynamicColorBuilder отдаёт lightDynamic/darkDynamic, только если
    // устройство умеет Material You (Android 12+) и такая тема
    // действительно настроена. Иначе оба будут null, и мы откатываемся
    // на обычную сгенерированную схему на основе seedColor.
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            return MaterialApp(
              title: 'ЭПОС',
              themeMode: themeController.mode,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: lightDynamic ??
                    ColorScheme.fromSeed(seedColor: Colors.indigo),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: darkDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: Colors.indigo,
                      brightness: Brightness.dark,
                    ),
              ),
              home: initialTokens == null
                  ? LoginScreen(themeController: themeController)
                  : HomeScreen(
                tokens: initialTokens!,
                themeController: themeController,
              ),
            );
          },
        );
      },
    );
  }
}