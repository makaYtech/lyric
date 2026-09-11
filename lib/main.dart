import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'core/theme/theme_controller.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = await ThemeController.load();
  runApp(EposApp(themeController: themeController));
}

class EposApp extends StatelessWidget {
  final ThemeController themeController;

  const EposApp({super.key, required this.themeController});

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
                colorScheme:
                    lightDynamic ?? ColorScheme.fromSeed(seedColor: Colors.indigo),
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
              home: LoginScreen(themeController: themeController),
            );
          },
        );
      },
    );
  }
}
