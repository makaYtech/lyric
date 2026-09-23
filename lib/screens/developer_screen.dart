import 'package:flutter/material.dart';

import '../core/auth/auth_config.dart';
import '../core/debug/debug_tools.dart';
import '../core/theme/theme_controller.dart';
import 'login_screen.dart';

/// Экран «Для разработчика». Попасть сюда можно только через
/// SettingsScreen → «Для разработчика» → предупреждение → OK.
class DeveloperScreen extends StatefulWidget {
  final ThemeController themeController;

  const DeveloperScreen({super.key, required this.themeController});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

/// Что выбрал юзер в модалке «Отравить…».
class _PoisonTarget {
  final String name;
  final bool isDeviceToken;
  const _PoisonTarget({required this.name, this.isDeviceToken = false});
}

/// Что выбрал юзер в модалке «Сбросить…».
enum _ResetTarget { deviceToken, oauthPair, longToken }

class _DeveloperScreenState extends State<DeveloperScreen> {
  final _tools = DebugTools.instance;

  late Future<DebugSnapshot> _snapshotFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _tools.snapshot();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _tools.snapshot();
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String successMessage,
    Future<void> Function()? afterAction,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _snack(successMessage);
      if (afterAction != null) {
        await afterAction();
      } else {
        _reload();
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    String confirmLabel = 'Сбросить',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _goToLogin() async {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(themeController: widget.themeController),
      ),
      (route) => false,
    );
  }

  // ── Авторизация ────────────────────────────────────────────────────────

  Future<void> _toggleAuthFlow(bool useDevice) async {
    final current = AuthConfig.useDeviceTokenFlow.value;
    if (current == useDevice) return;

    final ok = await _confirm(
      title: 'Сменить flow авторизации?',
      body: useDevice
          ? 'Включить device-token flow (новый). Текущая сессия будет '
                'сброшена — потребуется войти заново. Кэш и device_key '
                'останутся на месте.'
          : 'Включить legacy OAuth flow (PKCE + refresh_token + Phase C). '
                'Текущая сессия будет сброшена — потребуется войти заново. '
                'Используй, если новый flow не работает на стороне сервера.',
      confirmLabel: 'Сменить и выйти',
    );
    if (!ok) return;

    await AuthConfig.setUseDeviceTokenFlow(useDevice);
    await _tools.clearWholeEposSession();
    if (!mounted) return;
    _goToLogin();
  }

  // ── Сессия ЭПОС: отравление ───────────────────────────────────────────

  Future<void> _pickPoisonTarget() async {
    final snap = await _tools.snapshot();
    if (!mounted) return;

    final hasDeviceToken = (snap.epos?.deviceToken ?? '').isNotEmpty;
    final cookies = snap.cookies;

    if (!hasDeviceToken && cookies.isEmpty) {
      _snack('Нечего отравлять — сессии нет');
      return;
    }

    final picked = await showDialog<_PoisonTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Что отравить?'),
        children: [
          if (hasDeviceToken)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(
                const _PoisonTarget(
                  name: 'device_token (UUID)',
                  isDeviceToken: true,
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('device_token (UUID)'),
              ),
            ),
          if (hasDeviceToken && cookies.isNotEmpty) const Divider(height: 1),
          for (final name in cookies.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_PoisonTarget(name: name)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(name),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    if (picked.isDeviceToken) {
      await _run(
        _tools.poisonDeviceToken,
        successMessage: 'device_token отравлен',
      );
    } else {
      await _run(
        () => _tools.poisonCookie(picked.name),
        successMessage: 'Cookie "${picked.name}" отравлена',
      );
    }
  }

  // ── Сессия ЭПОС: сброс ────────────────────────────────────────────────

  Future<void> _pickResetTarget() async {
    final picked = await showDialog<_ResetTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Что сбросить?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.deviceToken),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('device_token (UUID)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.oauthPair),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('OAuth-пара (access + refresh)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.longToken),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('long_token'),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    switch (picked) {
      case _ResetTarget.deviceToken:
        await _run(
          _tools.clearDeviceToken,
          successMessage: 'device_token сброшен',
        );
      case _ResetTarget.oauthPair:
        await _run(
          _tools.clearOauthPair,
          successMessage: 'OAuth-пара сброшена',
        );
      case _ResetTarget.longToken:
        await _run(_tools.clearLongToken, successMessage: 'long_token сброшен');
    }
  }

  // ── Сессия ЭПОС: прочее ───────────────────────────────────────────────

  Future<void> _probeEndpoint() async {
    final controller = TextEditingController(
      text: '/core/api/profiles?ids=17938056',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Прямой запрос'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/core/api/...',
            labelText: 'Path',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty || !mounted) return;

    final result = await _tools.probe(path);
    if (!mounted) return;
    _snack('$path → $result');
    _reload();
  }

  Future<void> _forceRefresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _tools.forceSessionRefresh();
      if (!mounted) return;
      _snack(result);
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearWholeEposSession() async {
    final ok = await _confirm(
      title: 'Сбросить всю сессию ЭПОС?',
      body:
          'Полное удаление сессии. Приложение попадёт на LoginScreen '
          'при следующем перезапуске. Сейчас не редиректим — можно '
          'посмотреть, как отреагирует HomeScreen.',
    );
    if (!ok) return;
    await _run(
      _tools.clearWholeEposSession,
      successMessage: 'Сессия ЭПОС сброшена',
    );
  }

  // ── device_key ────────────────────────────────────────────────────────

  Future<void> _resetDeviceKey() async {
    final ok = await _confirm(
      title: 'Сбросить device_key?',
      body:
          'Следующий интерактивный вход сгенерирует новый ключ. '
          'Старый на сервере останется — сам по себе он бесполезен.',
    );
    if (!ok) return;
    await _run(_tools.resetDeviceKey, successMessage: 'device_key сброшен');
  }

  // ── Моя школа ─────────────────────────────────────────────────────────

  Future<void> _clearMySchool() async {
    final ok = await _confirm(
      title: 'Сбросить токены «Моей школы»?',
      body:
          'Если сейчас активен бэкенд «Моя школа», потребуется '
          'войти заново. Для ЭПОС-режима — просто очистка мусора.',
    );
    if (!ok) return;
    await _run(
      _tools.clearMySchoolTokens,
      successMessage: 'Токены «Моей школы» сброшены',
    );
  }

  // ── Кэш ───────────────────────────────────────────────────────────────

  Future<void> _clearProfileCache() async {
    await _run(_tools.clearProfileCache, successMessage: 'Кэш профиля сброшен');
  }

  Future<void> _clearYearsCache() async {
    await _run(
      _tools.clearAcademicYearsCache,
      successMessage: 'Кэш учебных годов сброшен',
    );
  }

  Future<void> _clearGroupsCache() async {
    await _run(
      _tools.clearStudentGroupsCache,
      successMessage: 'Кэш групп ученика сброшен',
    );
  }

  Future<void> _clearAvatars() async {
    final ok = await _confirm(
      title: 'Сбросить аватарки?',
      body:
          'Все локальные аватарки вернутся к инициалам. Файлы на '
          'устройстве не тронем — только ссылки в приложении.',
    );
    if (!ok) return;
    await _run(_tools.clearAvatarCache, successMessage: 'Аватарки сброшены');
  }

  Future<void> _resetDisplayPrefs() async {
    await _run(
      _tools.resetDisplayPrefs,
      successMessage: 'Настройки отображения сброшены',
    );
  }

  Future<void> _clearAllSharedPrefs() async {
    final ok = await _confirm(
      title: 'Снести все SharedPreferences?',
      body:
          'Кроме темы. Сюда попадают профиль, годы, группы, аватарки '
          'и все настройки. Кэш SQLite не тронем.',
    );
    if (!ok) return;
    await _run(
      _tools.clearAllSharedPrefs,
      successMessage: 'SharedPreferences очищены',
    );
  }

  // ── SQLite ────────────────────────────────────────────────────────────

  Future<void> _clearLessons() async {
    await _run(_tools.clearLessons, successMessage: 'Расписание очищено');
  }

  Future<void> _clearGrades() async {
    await _run(
      _tools.clearGrades,
      successMessage: 'Оценки (включая историю) очищены',
    );
  }

  Future<void> _clearMarks() async {
    await _run(_tools.clearMarks, successMessage: 'Marks очищены');
  }

  Future<void> _clearAttendances() async {
    await _run(_tools.clearAttendances, successMessage: 'Отсутствия очищены');
  }

  Future<void> _clearHomeworks() async {
    await _run(_tools.clearHomeworks, successMessage: 'ДЗ очищены');
  }

  Future<void> _clearTeachers() async {
    await _run(_tools.clearTeachers, successMessage: 'Учителя очищены');
  }

  Future<void> _clearWholeDatabase() async {
    final ok = await _confirm(
      title: 'Снести всю SQLite?',
      body:
          'Расписание, оценки, marks, ДЗ, учителя — всё. '
          'SharedPreferences останутся.',
    );
    if (!ok) return;
    await _run(_tools.clearWholeDatabase, successMessage: 'SQLite очищена');
  }

  // ── Опасная зона ──────────────────────────────────────────────────────

  Future<void> _fullWipe() async {
    final ok = await _confirm(
      title: 'Полный сброс?',
      body:
          'Сессия, кэш, SharedPreferences и вся SQLite будут стёрты. '
          'device_key и тема оформления останутся. Приложение вернётся '
          'на LoginScreen.',
      confirmLabel: 'Снести ВСЁ',
    );
    if (!ok) return;
    await _run(
      _tools.fullWipe,
      successMessage: 'Полный сброс выполнен',
      afterAction: _goToLogin,
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Для разработчика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Перечитать состояние',
            onPressed: _busy ? null : _reload,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const _WarningBanner(),
              const SizedBox(height: 16),

              _Section(
                title: 'Авторизация',
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AuthConfig.useDeviceTokenFlow,
                    builder: (context, useDevice, _) => SwitchListTile(
                      secondary: Icon(
                        useDevice
                            ? Icons.shield_moon_outlined
                            : Icons.history_edu_outlined,
                        color: useDevice
                            ? null
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: const Text('device-token flow'),
                      subtitle: Text(
                        useDevice
                            ? 'Новый: WebView → ESIA → diaryperm:// → '
                                  'три запроса /authenticate'
                            : 'Legacy: PKCE + refresh_token + Phase C '
                                  'через скрытый WebView',
                      ),
                      value: useDevice,
                      onChanged: _busy ? null : _toggleAuthFlow,
                    ),
                  ),
                  const ListTile(
                    dense: true,
                    leading: Icon(Icons.info_outline, size: 18),
                    title: Text(
                      'Смена flow сбрасывает текущую сессию и возвращает '
                      'на LoginScreen. Применяется при следующем входе.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),

              _Section(
                title: 'Сессия ЭПОС',
                children: [
                  FutureBuilder<DebugSnapshot>(
                    future: _snapshotFuture,
                    builder: (_, snap) =>
                        _SessionStatusTile(snapshot: snap.data),
                  ),
                  _ActionTile(
                    icon: Icons.bolt_outlined,
                    title: 'Отравить…',
                    subtitle: 'device_token или любую cookie',
                    enabled: !_busy,
                    onTap: _pickPoisonTarget,
                  ),
                  _ActionTile(
                    icon: Icons.restore,
                    title: 'Сбросить…',
                    subtitle: 'device_token, OAuth-пара, long_token',
                    enabled: !_busy,
                    onTap: _pickResetTarget,
                  ),
                  _ActionTile(
                    icon: Icons.wifi_tethering,
                    title: 'Прямой запрос (без renew)',
                    subtitle:
                        'В обход ApiClient и AuthCoordinator — '
                        'чистый ответ сервера на текущие cookies',
                    enabled: !_busy,
                    onTap: _probeEndpoint,
                  ),
                  _ActionTile(
                    icon: Icons.refresh,
                    title: 'Прогнать refresh прямо сейчас',
                    subtitle: 'Дёрнуть AuthCoordinator.renew() вручную',
                    enabled: !_busy,
                    onTap: _forceRefresh,
                  ),
                  _ActionTile(
                    icon: Icons.delete_forever,
                    title: 'Сбросить всю сессию ЭПОС',
                    subtitle: 'Secure storage + память',
                    enabled: !_busy,
                    onTap: _clearWholeEposSession,
                    danger: true,
                  ),
                ],
              ),

              _Section(
                title: 'device_key',
                children: [
                  FutureBuilder<DebugSnapshot>(
                    future: _snapshotFuture,
                    builder: (_, snap) =>
                        _KeyStatusTile(key_: snap.data?.deviceKey),
                  ),
                  _ActionTile(
                    icon: Icons.autorenew,
                    title: 'Сбросить device_key',
                    subtitle: 'Сгенерируется заново при следующем входе',
                    enabled: !_busy,
                    onTap: _resetDeviceKey,
                  ),
                ],
              ),

              _Section(
                title: 'Моя школа',
                children: [
                  FutureBuilder<DebugSnapshot>(
                    future: _snapshotFuture,
                    builder: (_, snap) => ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: const Text('Токены'),
                      subtitle: Text(
                        snap.data?.mySchoolTokensPresent == true
                            ? 'есть'
                            : 'нет',
                      ),
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.logout,
                    title: 'Сбросить токены «Моей школы»',
                    subtitle: 'acc_t / u / studentId',
                    enabled: !_busy,
                    onTap: _clearMySchool,
                  ),
                ],
              ),

              _Section(
                title: 'Кэш (SharedPreferences)',
                children: [
                  _ActionTile(
                    icon: Icons.person,
                    title: 'Профиль',
                    enabled: !_busy,
                    onTap: _clearProfileCache,
                  ),
                  _ActionTile(
                    icon: Icons.calendar_today,
                    title: 'Учебные годы',
                    enabled: !_busy,
                    onTap: _clearYearsCache,
                  ),
                  _ActionTile(
                    icon: Icons.group,
                    title: 'Группы ученика',
                    enabled: !_busy,
                    onTap: _clearGroupsCache,
                  ),
                  _ActionTile(
                    icon: Icons.image_outlined,
                    title: 'Аватарки',
                    subtitle: 'Ключи avatar:*, файлы на диске не трогаем',
                    enabled: !_busy,
                    onTap: _clearAvatars,
                  ),
                  _ActionTile(
                    icon: Icons.tune,
                    title: 'Настройки отображения',
                    subtitle: 'Пары, лимиты учителей, группировка ДЗ',
                    enabled: !_busy,
                    onTap: _resetDisplayPrefs,
                  ),
                  _ActionTile(
                    icon: Icons.delete_sweep,
                    title: 'Снести все SharedPreferences',
                    subtitle: 'Кроме темы оформления',
                    enabled: !_busy,
                    onTap: _clearAllSharedPrefs,
                    danger: true,
                  ),
                ],
              ),

              _Section(
                title: 'SQLite',
                children: [
                  _ActionTile(
                    icon: Icons.calendar_month,
                    title: 'Расписание',
                    enabled: !_busy,
                    onTap: _clearLessons,
                  ),
                  _ActionTile(
                    icon: Icons.grade,
                    title: 'Оценки (с историей)',
                    enabled: !_busy,
                    onTap: _clearGrades,
                  ),
                  _ActionTile(
                    icon: Icons.star_half,
                    title: 'Marks',
                    subtitle: 'Точки на расписании',
                    enabled: !_busy,
                    onTap: _clearMarks,
                  ),
                  _ActionTile(
                    icon: Icons.event_busy_outlined,
                    title: 'Отсутствия',
                    subtitle: 'Н-ки на расписании',
                    enabled: !_busy,
                    onTap: _clearAttendances,
                  ),
                  _ActionTile(
                    icon: Icons.book_outlined,
                    title: 'ДЗ',
                    enabled: !_busy,
                    onTap: _clearHomeworks,
                  ),
                  _ActionTile(
                    icon: Icons.school,
                    title: 'Учителя',
                    enabled: !_busy,
                    onTap: _clearTeachers,
                  ),
                  _ActionTile(
                    icon: Icons.storage,
                    title: 'Снести всю SQLite',
                    enabled: !_busy,
                    onTap: _clearWholeDatabase,
                    danger: true,
                  ),
                ],
              ),

              _Section(
                title: 'Опасная зона',
                danger: true,
                children: [
                  _ActionTile(
                    icon: Icons.delete_forever,
                    title: 'Полный сброс',
                    subtitle:
                        'Сессия + кэш + prefs + SQLite. '
                        'device_key и тема останутся',
                    enabled: !_busy,
                    onTap: _fullWipe,
                    danger: true,
                  ),
                ],
              ),
            ],
          ),
          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

// ── Виджеты ────────────────────────────────────────────────────────────

class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Какие-либо действия на этом экране могут привести к поломке '
              'работоспособности приложения. Настоятельно не '
              'рекомендуется трогать без нужды.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool danger;

  const _Section({
    required this.title,
    required this.children,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: danger ? theme.colorScheme.error : null,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Card(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : null;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: enabled ? onTap : null,
    );
  }
}

class _KeyStatusTile extends StatelessWidget {
  final String? key_;

  const _KeyStatusTile({required this.key_});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = key_ != null && key_!.isNotEmpty;
    final display = has ? 'есть (${key_!.length} симв.)' : '—';

    return ListTile(
      leading: const Icon(Icons.vpn_key_outlined),
      title: const Text('Текущий device_key'),
      subtitle: Text(
        display,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SessionStatusTile extends StatelessWidget {
  final DebugSnapshot? snapshot;

  const _SessionStatusTile({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = snapshot?.epos;

    if (s == null) {
      return ListTile(
        leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
        title: const Text('Сессия отсутствует'),
        subtitle: const Text('Secure storage пуст'),
      );
    }

    final oauth = s.refreshToken != null
        ? 'есть${s.accessExpiresAt != null ? " (${_expiresLabel(s.accessExpiresAt!)})" : ""}'
        : 'нет';

    final cookies = s.cookies;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(theme, 'Текущее состояние'),
          const SizedBox(height: 6),
          _row(
            theme,
            'flow',
            s.deviceToken != null ? 'device-token' : 'legacy OAuth',
          ),
          _row(theme, 'device_token', _presence(s.deviceToken)),
          _row(theme, 'auth_token (UUID)', _presence(s.authToken)),
          _row(theme, 'profile_id', s.profileId),
          _row(theme, 'OAuth-пара', oauth),
          const SizedBox(height: 12),
          _label(theme, 'Cookies (${cookies.length})'),
          const SizedBox(height: 6),
          if (cookies.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final entry in cookies.entries)
              _row(theme, entry.key, _cookieValue(entry.value)),
        ],
      ),
    );
  }

  static Widget _label(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.3,
    ),
  );

  /// "true"/"false" показываем как есть — длина бессмысленна.
  /// Остальное — "есть (N симв.)". Маркер POISONED_ подсвечиваем.
  static String _cookieValue(String v) {
    if (v.isEmpty) return '—';
    if (v == 'true' || v == 'false') return v;
    if (v.startsWith('POISONED_')) return 'ОТРАВЛЕНО';
    return 'есть (${v.length} симв.)';
  }

  static String _presence(String? v) {
    if (v == null || v.isEmpty) return '—';
    if (v.startsWith('POISONED_')) return 'ОТРАВЛЕНО';
    return 'есть (${v.length} симв.)';
  }

  static String _expiresLabel(DateTime exp) {
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'просрочен';
    if (diff.inMinutes < 1) return 'меньше минуты';
    if (diff.inHours < 1) return '${diff.inMinutes} мин';
    return '${diff.inHours} ч';
  }

  static Widget _row(ThemeData theme, String label, String value) {
    final isPoisoned = value == 'ОТРАВЛЕНО';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isPoisoned ? theme.colorScheme.error : null,
                fontWeight: isPoisoned ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
