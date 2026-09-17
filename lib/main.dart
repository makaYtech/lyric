import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/auth/auth_config.dart';
import 'core/auth/epos_session.dart';
import 'core/auth/myschool_token_storage.dart';
import 'core/auth/session_refresh_service.dart';
import 'core/backend/backends.dart';
import 'core/backend/backends_prefs.dart';
import 'core/settings/update_prefs.dart';
import 'core/theme/theme_controller.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/myschool_home_screen.dart';
import 'services/myschool/myschool_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final themeController = await ThemeController.load();
  await BackendPrefs.load();
  await AuthConfig.load();
  await UpdatePrefs.load();

  if (BackendPrefs.current.value == Backends.mySchool) {
    final msTokens = await MySchoolTokenStorage().load();
    runApp(
      EposApp(
        themeController: themeController,
        initialEposSession: null,
        initialMySchoolTokens: msTokens,
      ),
    );
    return;
  }

  // Пробуем поднять сессию из защищённого хранилища.
  // Если refresh_token жив — ensureFresh тихо обновит access,
  // если мёртв — вернёт null, и покажем LoginScreen.
  EposSession? session = await SessionRefreshService.instance.load();
  if (session != null) {
    session = await SessionRefreshService.instance.ensureFresh(session);
  }

  runApp(
    EposApp(
      themeController: themeController,
      initialEposSession: session,
      initialMySchoolTokens: null,
    ),
  );
}

class EposApp extends StatelessWidget {
  final ThemeController themeController;
  final EposSession? initialEposSession;
  final MySchoolTokens? initialMySchoolTokens;

  const EposApp({
    super.key,
    required this.themeController,
    required this.initialEposSession,
    this.initialMySchoolTokens,
  });

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return AnimatedBuilder(
          animation: themeController,
          builder: (context, _) {
            Widget home;
            if (initialMySchoolTokens != null) {
              home = MySchoolHomeScreen(
                tokens: initialMySchoolTokens!,
                themeController: themeController,
              );
            } else if (initialEposSession != null) {
              home = HomeScreen(
                session: initialEposSession!,
                themeController: themeController,
              );
            } else {
              home = LoginScreen(themeController: themeController);
            }
            return MaterialApp(
              title: 'ЭПОС',
              themeMode: themeController.mode,
              theme: ThemeData(
                useMaterial3: true,
                colorScheme:
                    lightDynamic ??
                    ColorScheme.fromSeed(seedColor: Colors.indigo),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme:
                    darkDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: Colors.indigo,
                      brightness: Brightness.dark,
                    ),
              ),
              home: home,
            );
          },
        );
      },
    );
  }
}
