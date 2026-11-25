import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_desktop_updater/flutter_desktop_updater.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import './core/auth/auth_config.dart';
import './core/auth/epos_session.dart';
import './core/auth/session_refresh_service.dart';
import './core/settings/layout_prefs.dart';
import './core/settings/update_prefs.dart';
import './core/theme/platform_style.dart';
import './core/theme/theme_controller.dart';
import './core/window/desktop_window.dart';
import './core/window/mica.dart';
import './features/home/home_screen.dart';
import './features/auth/login_screen.dart';

Future<void> main(List<String> args) async {
  // Окно входа desktop_webview_window запускает вторым экземпляром
  // приложения с особыми аргументами. Вызывать до ensureInitialized:
  // плагин делает runApp в своей зоне, иначе «Zone mismatch».
  if (runWebViewTitleBarWidget(args)) return;
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    UpdateConfig().configure(
      updateJsonUrl: 'https://raw.githubusercontent.com/makaYtech/lyric_apk/main/docs/desktop_update.json',
    );
    // Проверка идёт в фоне, чтобы не блокировать старт.
    unawaited(UpdateManager().checkForUpdate());
  }

  // Mica должна быть инициализирована до DesktopWindow.init().
  await Mica.init();

  await DesktopWindow.init();
  final themeController = await ThemeController.load();
  await AuthConfig.load();
  await UpdatePrefs.load();
  await LayoutPrefs.load();

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

            final useDynamic =
                themeController.useMaterialYou && lightDynamic != null;

            final lightScheme = useDynamic
                ? lightDynamic
                : ColorScheme.fromSeed(seedColor: Colors.indigo);

            final darkScheme =
                themeController.useMaterialYou && darkDynamic != null
                ? darkDynamic
                : ColorScheme.fromSeed(
                    seedColor: Colors.indigo,
                    brightness: Brightness.dark,
                  );

            return MaterialApp(
              title: 'ЭПОС',
              themeMode: themeController.mode,
              theme: applyPlatformStyle(
                ThemeData(useMaterial3: true, colorScheme: lightScheme),
              ),
              darkTheme: applyPlatformStyle(
                ThemeData(useMaterial3: true, colorScheme: darkScheme),
              ),
              builder: (context, child) {
                final body = child ?? const SizedBox.shrink();
                final isDesktop = Platform.isWindows || Platform.isLinux;

                return MicaScope(
                  child: isDesktop
                      ? Column(
                          children: [
                            // UpdateBanner сам управляет видимостью.
                            const UpdateBanner(),
                            Expanded(child: body),
                          ],
                        )
                      : body,
                );
              },
              home: home,
            );
          },
        );
      },
    );
  }
}
