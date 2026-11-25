import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/auth/session_notifier.dart';
import '../../core/auth/session_refresh_service.dart';
import '../../core/cache/cache_service.dart';
import '../../core/db/app_database.dart';
import '../../core/layout/adaptive.dart';
import '../../core/settings/layout_prefs.dart';
import '../../core/settings/avatar_storage.dart';
import '../../core/settings/schedule_prefs.dart';
import '../../core/settings/teacher_prefs.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/util/names.dart';
import '../../domain/people/teacher.dart';
import '../../widgets/common/person_avatar.dart';
import '../developer/developer_screen.dart';
import '../auth/login_screen.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../core/settings/update_prefs.dart';
import '../../data/services/feedback/feedback_service.dart';
import '../../services/update/update_service.dart';
import '../../widgets/feedback/feedback_sheet.dart';
import '../../widgets/update/update_sheet.dart';

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

  /// Подтверждение в диалоге; `danger` красит кнопку в цвет ошибки.
  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    IconData? icon,
    bool danger = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: icon == null ? null : Icon(icon, color: cs.error),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    )
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  static void _snack(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static void _replaceSnack(ScaffoldMessengerState messenger, String message) {
    messenger.hideCurrentSnackBar();
    _snack(messenger, message);
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: 'Выйти из аккаунта?',
      message:
          'Токены и все сохранённые данные (оценки, расписание, профиль) '
          'будут удалены с устройства. Чтобы вернуться, потребуется '
          'войти в ЭПОС заново.',
      confirmLabel: 'Выйти',
      danger: true,
    );
    if (!confirmed || !context.mounted) return;

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
        _snack(
          messenger,
          'Установлена последняя версия (${check.currentVersion})',
        );
      case UpdateCheckResult.available:
        final ok = await showUpdateSheet(context, check.info!);
        if (!ok && context.mounted) {
          _snack(messenger, 'Обновление отложено — можно вернуться сюда позже');
        }
      case UpdateCheckResult.networkError:
        _snack(
          messenger,
          'Не удалось проверить: ${check.error ?? "нет соединения"}',
        );
      case UpdateCheckResult.parseError:
        _snack(messenger, 'Ошибка разбора update.json: ${check.error}');
    }
  }

  static String _channelTitle(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Release',
    UpdateChannel.beta => 'Beta',
  };

  static String _channelDescription(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Стабильные версии (по умолчанию)',
    UpdateChannel.beta => 'Предрелизные версии',
  };

  static String _channelLabel(UpdateChannel c) => switch (c) {
    UpdateChannel.release => 'Release · стабильные',
    UpdateChannel.beta => 'Beta · предрелизные',
  };

  Future<void> _openFeedback(BuildContext context, FeedbackType type) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showFeedbackSheet(context, type);
    if (!sent) return;
    _replaceSnack(messenger, 'Спасибо! Отправлено');
  }

  Future<void> _resetStudentAvatar(BuildContext context) async {
    final key = studentAvatarKey;
    if (key == null) return;

    final confirmed = await _confirm(
      context,
      title: 'Сбросить аватар ученика?',
      message:
          'Аватар вернётся к инициалам. Файл на устройстве '
          'не тронем — только удалим ссылку в приложении.',
      confirmLabel: 'Сбросить',
    );
    if (!confirmed) return;

    await AvatarStorage.clear(key);
    if (!context.mounted) return;
    _snack(ScaffoldMessenger.of(context), 'Аватар ученика сброшен');
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
      final confirmed = await _confirm(
        context,
        title: 'Очистить аватары всех учителей?',
        message:
            'Сбросится ${list.length} ${_pluralTeachers(list.length)}. '
            'Файлы на устройстве не удаляются — только ссылки в приложении.',
        confirmLabel: 'Очистить',
      );
      if (!confirmed) return;

      for (final t in list) {
        await AvatarStorage.clear(AvatarStorage.teacherKey(t.id));
      }
      if (!context.mounted) return;
      _snack(
        ScaffoldMessenger.of(context),
        'Аватары всех учителей сброшены (${list.length})',
      );
      return;
    }

    final teacher = picked as Teacher;
    await AvatarStorage.clear(AvatarStorage.teacherKey(teacher.id));
    if (!context.mounted) return;
    _snack(
      ScaffoldMessenger.of(context),
      'Аватар ${shortTeacherName(teacher.fullName)} сброшен',
    );
  }

  Future<void> _openDeveloper(BuildContext context) async {
    final proceed = await _confirm(
      context,
      icon: Icons.warning_amber_rounded,
      title: 'Для разработчика',
      message:
          'Какие-либо действия на этой вкладке могут привести к поломке '
          'работоспособности приложения. Настоятельно не рекомендуется '
          'трогать без нужды.',
      confirmLabel: 'Понятно, войти',
      danger: true,
    );
    if (!proceed || !context.mounted) return;

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
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
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
            if (AdaptiveLayout.isDesktopOS) ...[
              _SectionHeader(
                icon: Icons.view_sidebar_outlined,
                title: 'Боковая панель',
              ),
              _SettingsCard(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: LayoutPrefs.sideBarOnRight,
                    builder: (_, right, _) => SwitchListTile(
                      title: const Text('Панель справа'),
                      subtitle: const Text('По умолчанию — слева'),
                      value: right,
                      onChanged: LayoutPrefs.setSideBarOnRight,
                    ),
                  ),
                  const Divider(height: 1),
                  ValueListenableBuilder<bool>(
                    valueListenable: LayoutPrefs.sideBarExpanded,
                    builder: (_, expanded, _) => SwitchListTile(
                      title: const Text('Показывать названия'),
                      subtitle: const Text(
                        'То же, что кнопка раскрытия вверху панели',
                      ),
                      value: expanded,
                      onChanged: LayoutPrefs.setSideBarExpanded,
                    ),
                  ),
                ],
              ),
            ],
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
            _SectionHeader(
              icon: Icons.feedback_outlined,
              title: 'Обратная связь',
            ),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Сообщить об ошибке'),
                  subtitle: const Text('Что-то сломалось или работает не так'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFeedback(context, FeedbackType.bug),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: const Text('Отзыв или предложение'),
                  subtitle: const Text(
                    'Идея, пожелание или впечатление о приложении',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFeedback(context, FeedbackType.request),
                ),
              ],
            ),
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

/// Заголовок секции: иконка + текст.
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

/// Подзаголовок внутри карточки — разделяет связанные группы настроек.
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

/// Карточка с настройками. Divider'ы между элементами передаёт вызывающий.
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
