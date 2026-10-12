import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/auth/session_notifier.dart';
import '../core/auth/session_refresh_service.dart';
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

import 'package:package_info_plus/package_info_plus.dart';

import '../core/settings/update_prefs.dart';
import '../services/update/update_service.dart';
import '../widgets/update/update_sheet.dart';

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

  // ── Действия ──────────────────────────────────────────────────────────

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
    } catch (_) {}

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
              title: Text(v == TeacherPrefs.allValue ? 'Показать всё' : '$v'),
              value: v,
              groupValue: current,
              onChanged: (x) => Navigator.of(ctx).pop(x),
            ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickGapThreshold(BuildContext context) async {
    final current = SchedulePrefs.gapThresholdMinutes.value;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Порог окна'),
        children: [
          for (final v in SchedulePrefs.gapThresholdOptions)
            RadioListTile<int>(
              title: Text('Больше $v мин'),
              value: v,
              groupValue: current,
              onChanged: (x) => Navigator.of(ctx).pop(x),
            ),
        ],
      ),
    );
    if (picked != null) SchedulePrefs.setGapThresholdMinutes(picked);
  }

  // ── Обновления ────────────────────────────────────────────────────────

  Future<void> _pickChannel(BuildContext context) async {
    final current = UpdatePrefs.channel.value;
    final picked = await showDialog<UpdateChannel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Канал обновлений'),
        children: [
          for (final c in UpdateChannel.values)
            RadioListTile<UpdateChannel>(
              title: Text(_channelTitle(c)),
              subtitle: Text(_channelDescription(c)),
              value: c,
              groupValue: current,
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
        ],
      ),
    );
    if (picked != null) {
      await UpdatePrefs.setChannel(picked);
    }
  }

  Future<void> _checkUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Проверяем обновления…'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );

    final check = await UpdateService.instance.check(UpdatePrefs.channel.value);
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();

    switch (check.result) {
      case UpdateCheckResult.upToDate:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Установлена последняя версия '
              '(${check.currentVersion})',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case UpdateCheckResult.available:
        final ok = await showUpdateSheet(context, check.info!);
        if (!ok && context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Обновление отложено — можно вернуться сюда позже'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      case UpdateCheckResult.networkError:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Не удалось проверить: ${check.error ?? "нет соединения"}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case UpdateCheckResult.parseError:
        messenger.showSnackBar(
          SnackBar(
            content: Text('Ошибка разбора update.json: ${check.error}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  static String _channelTitle(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Release',
    UpdateChannel.beta => 'Beta',
    UpdateChannel.alpha => 'Alpha',
  };

  static String _channelDescription(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Стабильные версии (по умолчанию)',
    UpdateChannel.beta => 'Предрелизные версии',
    UpdateChannel.alpha => 'Экспериментальные версии',
  };

  static String _channelLabel(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Release · стабильные',
    UpdateChannel.beta => 'Beta · предрелизные',
    UpdateChannel.alpha => 'Alpha · экспериментальные',
  };

  // ── Аватарки ──────────────────────────────────────────────────────────

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

  // ── Для разработчика ──────────────────────────────────────────────────

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

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            // 1. Внешний вид
            _SectionHeader(icon: Icons.palette_outlined, title: 'Внешний вид'),
            _SettingsCard(
              children: [
                RadioListTile<AppThemeChoice>(
                  title: const Text('Светлая'),
                  value: AppThemeChoice.light,
                  groupValue: themeController.choice,
                  onChanged: (v) => themeController.setChoice(v!),
                ),
                const Divider(height: 1),
                RadioListTile<AppThemeChoice>(
                  title: const Text('Тёмная'),
                  value: AppThemeChoice.dark,
                  groupValue: themeController.choice,
                  onChanged: (v) => themeController.setChoice(v!),
                ),
                const Divider(height: 1),
                RadioListTile<AppThemeChoice>(
                  title: const Text('Как в системе'),
                  subtitle: const Text(
                    'Следует светлой/тёмной теме устройства. '
                    'Цвета приложения фиксированные',
                  ),
                  value: AppThemeChoice.system,
                  groupValue: themeController.choice,
                  onChanged: (v) => themeController.setChoice(v!),
                ),
                const Divider(height: 1),
                RadioListTile<AppThemeChoice>(
                  title: const Text('Material You'),
                  subtitle: const Text(
                    'Тема и акцентные цвета берутся у устройства (Android 12+). '
                    'Следует системной светлой/тёмной теме',
                  ),
                  value: AppThemeChoice.material,
                  groupValue: themeController.choice,
                  onChanged: (v) => themeController.setChoice(v!),
                ),
              ],
            ),
            // 2. Расписание
            _SectionHeader(
              icon: Icons.calendar_today_outlined,
              title: 'Расписание',
            ),
            _SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: SchedulePrefs.mergePairs,
                  builder: (context, merge, _) => SwitchListTile(
                    title: const Text('Объединять уроки в пары'),
                    subtitle: const Text(
                      'Если два одинаковых урока подряд (тот же предмет, '
                      'учитель и кабинет) — показывать одной карточкой',
                    ),
                    value: merge,
                    onChanged: SchedulePrefs.setMergePairs,
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: SchedulePrefs.showOverrides,
                  builder: (context, value, _) => SwitchListTile(
                    title: const Text('Показывать мои правки'),
                    subtitle: const Text(
                      'Выключи, чтобы увидеть расписание строго как на '
                      'сервере. Правки не удалятся и вернутся при '
                      'включении обратно',
                    ),
                    value: value,
                    onChanged: SchedulePrefs.setShowOverrides,
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: SchedulePrefs.showGaps,
                  builder: (context, value, _) => SwitchListTile(
                    title: const Text('Показывать окна'),
                    subtitle: const Text(
                      'Между уроками с большим перерывом показывается '
                      'карточка «Окно»',
                    ),
                    value: value,
                    onChanged: SchedulePrefs.setShowGaps,
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<int>(
                  valueListenable: SchedulePrefs.gapThresholdMinutes,
                  builder: (context, value, _) => ListTile(
                    title: const Text('Порог окна'),
                    subtitle: Text('Больше $value мин перерыва — окно'),
                    enabled: SchedulePrefs.showGaps.value,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickGapThreshold(context),
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: SchedulePrefs.autoScrollToToday,
                  builder: (context, value, _) => SwitchListTile(
                    title: const Text('Перелистывать на текущий день'),
                    subtitle: const Text(
                      'При первом заходе на вкладку «Расписание» '
                      'прокручивать к сегодняшнему дню',
                    ),
                    value: value,
                    onChanged: SchedulePrefs.setAutoScrollToToday,
                  ),
                ),
              ],
            ),

            // 3. Профиль
            _SectionHeader(icon: Icons.person_outline, title: 'Профиль'),
            _SettingsCard(
              children: [
                if (studentAvatarKey != null) ...[
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('Сбросить аватар ученика'),
                    subtitle: const Text(
                      'Вернуть инициалы. Файл на устройстве не удаляется',
                    ),
                    onTap: () => _resetStudentAvatar(context),
                  ),
                ],
                if (studentAvatarKey != null &&
                    teachers != null &&
                    teachers!.isNotEmpty)
                  const Divider(height: 1),
                if (teachers != null && teachers!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('Сбросить аватар учителя'),
                    subtitle: const Text('Выбрать из списка'),
                    onTap: () => _resetTeacherAvatar(context),
                  ),
                if (studentAvatarKey != null ||
                    (teachers != null && teachers!.isNotEmpty))
                  const _SubHeader('Учителя в карточке'),
                ValueListenableBuilder<bool>(
                  valueListenable: TeacherPrefs.onlyStudentTeachers,
                  builder: (context, value, _) => SwitchListTile(
                    title: const Text('Только мои учителя'),
                    subtitle: const Text(
                      'Показывать только тех, кто ведёт уроки у этого '
                      'ученика',
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
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickLimit(
                      context,
                      title: 'Предметов в карточке',
                      current: limit,
                      onPicked: TeacherPrefs.setSubjectsLimit,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<int>(
                  valueListenable: TeacherPrefs.roomsLimit,
                  builder: (context, limit, _) => ListTile(
                    title: const Text('Кабинетов в карточке'),
                    subtitle: Text(TeacherPrefs.limitLabel(limit)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickLimit(
                      context,
                      title: 'Кабинетов в карточке',
                      current: limit,
                      onPicked: TeacherPrefs.setRoomsLimit,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: TeacherPrefs.showOldRooms,
                  builder: (context, value, _) => SwitchListTile(
                    title: const Text('Показывать старые кабинеты'),
                    subtitle: const Text(
                      'По умолчанию виден только текущий кабинет, где '
                      'учитель ответственный. Включи, чтобы показать все '
                      'кабинеты из истории',
                    ),
                    value: value,
                    onChanged: TeacherPrefs.setShowOldRooms,
                  ),
                ),
              ],
            ),

            // 4. Обновления
            _SectionHeader(
              icon: Icons.system_update_outlined,
              title: 'Обновления',
            ),
            _SettingsCard(
              children: [
                ValueListenableBuilder<UpdateChannel>(
                  valueListenable: UpdatePrefs.channel,
                  builder: (context, channel, _) => ListTile(
                    title: const Text('Канал обновлений'),
                    subtitle: Text(_channelLabel(channel)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickChannel(context),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('Проверить обновление'),
                  subtitle: const Text(
                    'Вручную проверить выбранный канал и установить '
                    'новую версию',
                  ),
                  onTap: () => _checkUpdates(context),
                ),
              ],
            ),

            // 5. Аккаунт
            _SectionHeader(
              icon: Icons.account_circle_outlined,
              title: 'Аккаунт',
            ),
            _SettingsCard(
              children: [
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
            ),

            // 6. О приложении
            _SectionHeader(icon: Icons.info_outline, title: 'О приложении'),
            _SettingsCard(
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) => ListTile(
                    leading: const Icon(Icons.numbers),
                    title: const Text('Версия'),
                    subtitle: Text(
                      snap.hasData
                          ? '${snap.data!.version} '
                                '(сборка ${snap.data!.buildNumber})'
                          : '—',
                    ),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Автор'),
                  subtitle: Text('makaYtech'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Репозиторий'),
                  subtitle: Text('github.com/makaYtech/lyric_apk'),
                ),
              ],
            ),

            // 7. Для разработчика
            _SectionHeader(
              icon: Icons.bug_report_outlined,
              title: 'Для разработчика',
              danger: true,
            ),
            _SettingsCard(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Опасные операции'),
                  subtitle: const Text(
                    'Сброс токенов, кэша и БД по частям. Может сломать '
                    'приложение',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openDeveloper(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Виджеты секций ──────────────────────────────────────────────────────

/// Заголовок секции: иконка + текст. Стоит над карточкой.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool danger;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Маленький подзаголовок внутри карточки — разделяет связанные группы
/// настроек (например, «Аватарки» и «Учителя» внутри «Профиля»).
class _SubHeader extends StatelessWidget {
  final String title;

  const _SubHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Карточка с настройками. Внутри — дети через Divider'ы (передавай их
/// сам между элементами, если нужны). Все элементы — ListTile и его
/// вариации, без дополнительной обёртки.
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
