import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/auth/auth_config.dart';
import 'core/auth/epos_session.dart';
import 'core/auth/session_refresh_service.dart';
import 'core/settings/layout_prefs.dart';
import 'core/settings/update_prefs.dart';
import 'core/theme/theme_controller.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main(List<String> args) async {
  // desktop_webview_window запускает окно входа как второй экземпляр
  // приложения с особыми аргументами — такой запуск обрабатывается тут
  // и дальше (БД, сессия, runApp) не идёт. Вызываем ДО ensureInitialized:
  // плагин запускает runApp в своей зоне, иначе «Zone mismatch».
  if (runWebViewTitleBarWidget(args)) return;
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final themeController = await ThemeController.load();
  await AuthConfig.load();
  await UpdatePrefs.load();
  await LayoutPrefs.load();

  // Пробуем поднять сессию из защищённого хранилища.
  // Если refresh_token жив — ensureFresh тихо обновит access,
  // если мёртв — вернёт null, и покажем LoginScreen.
  EposSession? session = await SessionRefreshService.instance.load();
  if (session != null) {
    session = await SessionRefreshService.instance.ensureFresh(session);
  }

  runApp(
    EposApp(themeController: themeController, initialEposSession: session),
  );
}

class EposApp extends StatelessWidget {
  final ThemeController themeController;
  final EposSession? initialEposSession;

  const EposApp({
    super.key,
    required this.themeController,
    required this.initialEposSession,
  });

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            final home = initialEposSession != null
                ? HomeScreen(
                    session: initialEposSession!,
                    themeController: themeController,
                  )
                : LoginScreen(themeController: themeController);

            // Динамические цвета подключаем ТОЛЬКО в режиме «Material».
            // Для light/dark/system всегда идёт фиксированный seed, чтобы
            // акцентные цвета не «протекали» в обычные темы.
            final useDynamic =
                themeController.useMaterialYou && lightDynamic != null;

            final lightScheme = useDynamic
                ? lightDynamic!
                : ColorScheme.fromSeed(seedColor: Colors.indigo);

            final darkScheme =
                themeController.useMaterialYou && darkDynamic != null
                ? darkDynamic!
                : ColorScheme.fromSeed(
                    seedColor: Colors.indigo,
                    brightness: Brightness.dark,
                  );

            return MaterialApp(
              title: 'ЭПОС',
              themeMode: themeController.mode,
              theme: ThemeData(useMaterial3: true, colorScheme: lightScheme),
              darkTheme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
              home: home,
            );
          },
        );
      },
    );
  }
}
