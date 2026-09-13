import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/session_notifier.dart';
import '../core/auth/token_storage.dart';
import '../core/backend/backends.dart';
import '../core/backend/backends_prefs.dart';
import '../core/cache/cache_service.dart';
import '../core/db/app_database.dart';
import '../core/settings/schedule_prefs.dart';
import '../core/theme/theme_controller.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;

  const SettingsScreen({super.key, required this.themeController});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Токены и все сохранённые данные (оценки, расписание, профиль) '
              'будут удалены с устройства. Чтобы вернуться, потребуется '
              'войти в ЭПОС заново.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await WebViewCookieManager().clearCookies();
    } catch (_) {
      // Не критично: даже если не получилось — TokenStorage всё равно
      // будет очищен, а LoginScreen загрузит форму входа.
    }

    await TokenStorage().clear();
    await CacheService().clearAll();
    await AppDatabase.instance.clearAll();
    SessionNotifier.instance.reset();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(themeController: themeController),
      ),
          (route) => false,
    );
  }

  /// Диалог выбора источника данных. Пока реально доступен только ЭПОС;
  /// «Моя школа» показывается, но заблокирована — чтобы точка расширения
  /// была видна сразу и не забылась.
  Future<void> _pickBackend(BuildContext context) async {
    final currentId = BackendPrefs.current.value;

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Endpoint service'),
        children: [
          for (final b in Backends.all)
            RadioListTile<String>(
              title: Text(b.displayName),
              subtitle: Text(b.description),
              value: b.id,
              groupValue: currentId,
              // onChanged=null выключает тайл — визуально видно,
              // что пункт недоступен.
              onChanged:
              b.available ? (v) => Navigator.of(ctx).pop(v) : null,
            ),
        ],
      ),
    );

    if (chosen == null || chosen == currentId) return;

    // Сюда мы попадём только если «Мою школу» когда-нибудь включат.
    // На этот момент смена источника данных означает другой auth —
    // надо будет сбросить токены и заставить юзера войти заново.
    // Пока это TODO: реализуем вместе с настоящим MySchoolAuth.
    await BackendPrefs.set(chosen);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Источник данных: ${Backends.byId(chosen).displayName}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) {
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Тема оформления',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Светлая'),
                value: ThemeMode.light,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Тёмная'),
                value: ThemeMode.dark,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Как в системе'),
                subtitle: const Text(
                  'Следует теме устройства. На Android 12+ подхватывает '
                      'акцентные цвета твоей темы (Material You), если система их отдаёт',
                ),
                value: ThemeMode.system,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Расписание',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: SchedulePrefs.mergePairs,
                builder: (context, merge, _) => SwitchListTile(
                  title: const Text('Объединять уроки в пары'),
                  subtitle: const Text(
                    'Если два одинаковых урока подряд (тот же предмет, '
                        'учитель и кабинет) — показывать их одной карточкой',
                  ),
                  value: merge,
                  onChanged: SchedulePrefs.setMergePairs,
                ),
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Источник данных',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: BackendPrefs.current,
                builder: (context, currentId, _) {
                  final info = Backends.byId(currentId);
                  return ListTile(
                    title: const Text('Endpoint service'),
                    subtitle: Text(info.displayName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickBackend(context),
                  );
                },
              ),
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Аккаунт',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.logout,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Выйти из аккаунта',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () => _logout(context),
              ),
            ],
          );
        },
      ),
    );
  }
}