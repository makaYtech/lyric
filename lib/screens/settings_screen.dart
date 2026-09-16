import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/session_notifier.dart';
import '../core/auth/session_refresh_service.dart';
import '../core/backend/backends.dart';
import '../core/backend/backends_prefs.dart';
import '../core/cache/cache_service.dart';
import '../core/db/app_database.dart';
import '../core/settings/avatar_storage.dart';
import '../core/settings/schedule_prefs.dart';
import '../core/settings/teacher_prefs.dart';
import '../core/theme/theme_controller.dart';
import '../core/util/names.dart';
import '../models/teacher.dart';
import '../widgets/common/person_avatar.dart';
import 'developer_screen.dart';
import 'login_screen.dart';
import '../core/auth/myschool_token_storage.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;

  final String? studentAvatarKey;

  final List<Teacher>? teachers;

  const SettingsScreen({
    super.key,
    required this.themeController,
    this.studentAvatarKey,
    this.teachers,
  });

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
      // Не критично.
    }

    await SessionRefreshService.instance.clear();
    await CacheService().clearAll();
    AvatarStorage.invalidateAll();
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
              onChanged: b.available ? (v) => Navigator.of(ctx).pop(v) : null,
            ),
        ],
      ),
    );

    if (chosen == null || chosen == currentId) return;

    await BackendPrefs.set(chosen);

    await SessionRefreshService.instance.clear();
    await MySchoolTokenStorage().clear();
    AvatarStorage.invalidateAll();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(themeController: themeController),
      ),
          (route) => false,
    );
  }

  Future<void> _pickLimit(
      BuildContext context, {
        required String title,
        required int current,
        required ValueChanged<int> onPicked,
      }) async {
    const options = <int>[3, 5, 10, TeacherPrefs.allValue];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final v in options)
            RadioListTile<int>(
              title: Text(
                v == TeacherPrefs.allValue ? 'Показать всё' : '$v',
              ),
              value: v,
              groupValue: current,
              onChanged: (x) => Navigator.of(ctx).pop(x),
            ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _resetStudentAvatar(BuildContext context) async {
    final key = studentAvatarKey;
    if (key == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить аватар ученика?'),
        content: const Text(
          'Аватар вернётся к инициалам. Файл на устройстве '
              'не тронем — только удалим ссылку в приложении.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AvatarStorage.clear(key);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Аватар ученика сброшен'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _resetTeacherAvatar(BuildContext context) async {
    final list = teachers;
    if (list == null || list.isEmpty) return;

    final picked = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Сбросить аватар учителя'),
        children: [
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Очистить у всех'),
            subtitle: const Text('Сбросить все аватары учителей сразу'),
            onTap: () => Navigator.of(ctx).pop(_clearAllTeachersSentinel),
          ),
          const Divider(height: 1),
          SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  return ListTile(
                    leading: PersonAvatar(
                      fullName: t.fullName,
                      radius: 18,
                      avatarKey: AvatarStorage.teacherKey(t.id),
                    ),
                    title: Text(shortTeacherName(t.fullName)),
                    onTap: () => Navigator.of(ctx).pop(t),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );

    if (picked == null || !context.mounted) return;

    if (identical(picked, _clearAllTeachersSentinel)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Очистить аватары всех учителей?'),
          content: Text(
            'Сбросится ${list.length} ${_pluralTeachers(list.length)}. '
                'Файлы на устройстве не удаляются — только ссылки в приложении.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Очистить'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      for (final t in list) {
        await AvatarStorage.clear(AvatarStorage.teacherKey(t.id));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Аватары всех учителей сброшены (${list.length})'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final teacher = picked as Teacher;
    await AvatarStorage.clear(AvatarStorage.teacherKey(teacher.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Аватар ${shortTeacherName(teacher.fullName)} сброшен'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Предупреждение + переход на DeveloperScreen. Предупреждение
  /// показывается ровно один раз при входе — внутри экрана уже нет
  /// дополнительных блокировок.
  Future<void> _openDeveloper(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
        ),
        title: const Text('Для разработчика'),
        content: const Text(
          'Какие-либо действия на этой вкладке могут привести к поломке '
              'работоспособности приложения. Настоятельно не рекомендуется '
              'трогать без нужды.',
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
            child: const Text('Понятно, войти'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeveloperScreen(themeController: themeController),
      ),
    );
  }

  static final _clearAllTeachersSentinel = Object();

  String _pluralTeachers(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'учитель';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'учителя';
    }
    return 'учителей';
  }

  @override
  Widget build(BuildContext context) {
    final hasStudentAvatar = studentAvatarKey != null;
    final hasTeachers = teachers != null && teachers!.isNotEmpty;

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
                  'Профиль',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Аватарки',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasStudentAvatar)
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('Сбросить аватар ученика'),
                  subtitle: const Text(
                    'Вернуть инициалы. Файл на устройстве не удаляется',
                  ),
                  onTap: () => _resetStudentAvatar(context),
                ),
              if (hasTeachers)
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Сбросить аватар учителя'),
                  subtitle: const Text('Выбрать из списка'),
                  onTap: () => _resetTeacherAvatar(context),
                ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Учителя',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: TeacherPrefs.onlyStudentTeachers,
                builder: (context, value, _) => SwitchListTile(
                  title: const Text('Только мои учителя'),
                  subtitle: const Text(
                    'Показывать только тех, кто ведёт уроки у этого '
                        'ученика. Список строится по расписанию, '
                        'сохранённому на устройстве',
                  ),
                  value: value,
                  onChanged: TeacherPrefs.setOnlyStudentTeachers,
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<int>(
                valueListenable: TeacherPrefs.subjectsLimit,
                builder: (context, limit, _) => ListTile(
                  title: const Text('Предметов в карточке'),
                  subtitle: Text(TeacherPrefs.limitLabel(limit)),
                  onTap: () => _pickLimit(
                    context,
                    title: 'Предметов в карточке',
                    current: limit,
                    onPicked: TeacherPrefs.setSubjectsLimit,
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: TeacherPrefs.roomsLimit,
                builder: (context, limit, _) => ListTile(
                  title: const Text('Кабинетов в карточке'),
                  subtitle: Text(TeacherPrefs.limitLabel(limit)),
                  onTap: () => _pickLimit(
                    context,
                    title: 'Кабинетов в карточке',
                    current: limit,
                    onPicked: TeacherPrefs.setRoomsLimit,
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: TeacherPrefs.showOldRooms,
                builder: (context, value, _) => SwitchListTile(
                  title: const Text('Показывать старые кабинеты'),
                  subtitle: const Text(
                    'Учителя со временем меняли кабинеты. По умолчанию '
                        'виден только текущий, где он ответственный. Включи, '
                        'чтобы показать все кабинеты из истории',
                  ),
                  value: value,
                  onChanged: TeacherPrefs.setShowOldRooms,
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
              const Divider(height: 32),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Для разработчика',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.bug_report_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Для разработчика'),
                subtitle: const Text(
                  'Настройки, которые ненужно менять',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDeveloper(context),
              ),
            ],
          );
        },
      ),
    );
  }
}