import 'package:flutter/material.dart';

import '../core/auth/auth_config.dart';
import '../core/debug/debug_tools.dart';
import '../core/theme/theme_controller.dart';
import 'login_screen.dart';

/// Экран «Для разработчика». Попасть сюда можно только через
/// SettingsScreen → «Для разработчика» → предупреждение → OK.
///
/// Здесь нет никаких правил UX: кнопки могут убить сессию, стереть кэш,
/// сменить текущее состояние. Единственное, что мы делаем для
/// безопасности — подтверждения на опасных действиях и snackbar с
/// результатом.
///
/// ВАЖНО: токены и ключи тут НИКОГДА не показываются целиком или
/// по частям. Только факт наличия и длина. Префикс — это тоже часть
/// секрета, и он точно так же утекает через скриншоты и issue-трекеры.
class DeveloperScreen extends StatefulWidget {
  final ThemeController themeController;

  const DeveloperScreen({super.key, required this.themeController});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

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

  /// Обёртка: запускает действие, блокирует кнопки, показывает результат.
  /// [successMessage] — что сказать при успехе; [afterAction] — что
  /// сделать после (например, редирект на LoginScreen для полного сброса).
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

  // ── Обработчики ────────────────────────────────────────────────────────

  /// Переключение flow. Сбрасываем текущую сессию, потому что:
  ///   - иначе пользователь не увидит эффекта (сессия продолжит жить
  ///     тем flow, которым была получена);
  ///   - при смене flow логично начать с чистого листа — вдруг на
  ///     другом flow refresh-логика несовместима с тем, что лежит в БД.
  ///
  /// Флаг сохраняется в prefs и применяется на следующем логине.
  /// Кэш и device_key не трогаем — они не привязаны к flow.
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

  Future<void> _clearDeviceToken() async {
    final ok = await _confirm(
      title: 'Сбросить device_token?',
      body: 'auth_token останется живым, но при первом 401 обновить '
          'сессию уже не получится — упрёмся в ReauthSheet. Это и есть '
          'проверка граничного случая.',
    );
    if (!ok) return;
    await _run(
      _tools.clearDeviceToken,
      successMessage: 'device_token сброшен',
    );
  }

  Future<void> _poisonAuthToken() async {
    final ok = await _confirm(
      title: 'Отравить auth_token?',
      body: 'Следующий запрос к API получит 401. Если новый flow '
          'действительно самовосстанавливающийся — оно тут же поменяет '
          'auth_token на свежий. Если нет — покажет ReauthSheet.',
      confirmLabel: 'Отравить',
    );
    if (!ok) return;
    await _run(
      _tools.poisonAuthToken,
      successMessage: 'auth_token заменён на мусор',
    );
  }

  Future<void> _clearOauthPair() async {
    final ok = await _confirm(
      title: 'Сбросить OAuth-пару?',
      body: 'access_token, refresh_token и время истечения будут удалены. '
          'Для device-token-сессии это безвредно, для legacy — сломает '
          'refresh.',
    );
    if (!ok) return;
    await _run(
      _tools.clearOauthPair,
      successMessage: 'OAuth-пара сброшена',
    );
  }

  Future<void> _clearLongToken() async {
    final ok = await _confirm(
      title: 'Сбросить long_token?',
      body: 'long_token удаляется, остальные поля сессии остаются.',
    );
    if (!ok) return;
    await _run(
      _tools.clearLongToken,
      successMessage: 'long_token сброшен',
    );
  }

  Future<void> _clearWholeEposSession() async {
    final ok = await _confirm(
      title: 'Сбросить всю сессию ЭПОС?',
      body: 'Полное удаление сессии. Приложение попадёт на LoginScreen '
          'при следующем перезапуске. Сейчас не редиректим — можно '
          'посмотреть, как отреагирует HomeScreen.',
    );
    if (!ok) return;
    await _run(
      _tools.clearWholeEposSession,
      successMessage: 'Сессия ЭПОС сброшена',
    );
  }

  Future<void> _resetDeviceKey() async {
    final ok = await _confirm(
      title: 'Сбросить device_key?',
      body: 'Следующий интерактивный вход сгенерирует новый ключ. '
          'Старый на сервере останется — сам по себе он бесполезен.',
    );
    if (!ok) return;
    await _run(
      _tools.resetDeviceKey,
      successMessage: 'device_key сброшен',
    );
  }

  Future<void> _clearMySchool() async {
    final ok = await _confirm(
      title: 'Сбросить токены «Моей школы»?',
      body: 'Если сейчас активен бэкенд «Моя школа», потребуется '
          'войти заново. Для ЭПОС-режима — просто очистка мусора.',
    );
    if (!ok) return;
    await _run(
      _tools.clearMySchoolTokens,
      successMessage: 'Токены «Моей школы» сброшены',
    );
  }

  Future<void> _clearProfileCache() async {
    await _run(
      _tools.clearProfileCache,
      successMessage: 'Кэш профиля сброшен',
    );
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
      body: 'Все локальные аватарки вернутся к инициалам. Файлы на '
          'устройстве не тронем — только ссылки в приложении.',
    );
    if (!ok) return;
    await _run(
      _tools.clearAvatarCache,
      successMessage: 'Аватарки сброшены',
    );
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
      body: 'Кроме темы. Сюда попадают профиль, годы, группы, аватарки '
          'и все настройки. Кэш SQLite не тронем.',
    );
    if (!ok) return;
    await _run(
      _tools.clearAllSharedPrefs,
      successMessage: 'SharedPreferences очищены',
    );
  }

  Future<void> _clearLessons() async {
    await _run(
      _tools.clearLessons,
      successMessage: 'Расписание очищено',
    );
  }

  Future<void> _clearGrades() async {
    await _run(
      _tools.clearGrades,
      successMessage: 'Оценки (включая историю) очищены',
    );
  }

  Future<void> _clearMarks() async {
    await _run(
      _tools.clearMarks,
      successMessage: 'Marks очищены',
    );
  }

  Future<void> _clearHomeworks() async {
    await _run(
      _tools.clearHomeworks,
      successMessage: 'ДЗ очищены',
    );
  }

  Future<void> _clearTeachers() async {
    await _run(
      _tools.clearTeachers,
      successMessage: 'Учителя очищены',
    );
  }

  Future<void> _clearWholeDatabase() async {
    final ok = await _confirm(
      title: 'Снести всю SQLite?',
      body: 'Расписание, оценки, marks, ДЗ, учителя — всё. '
          'SharedPreferences останутся.',
    );
    if (!ok) return;
    await _run(
      _tools.clearWholeDatabase,
      successMessage: 'SQLite очищена',
    );
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

  Future<void> _fullWipe() async {
    final ok = await _confirm(
      title: 'Полный сброс?',
      body: 'Сессия, кэш, SharedPreferences и вся SQLite будут стёрты. '
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
                            '/authenticate с заголовком token'
                            : 'Legacy: PKCE + refresh_token + Phase C '
                            'через скрытый WebView',
                      ),
                      value: useDevice,
                      onChanged: _busy ? null : _toggleAuthFlow,
                    ),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline, size: 18),
                    title: const Text(
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
                    icon: Icons.link_off,
                    title: 'Сбросить device_token',
                    subtitle:
                    'Ломает авто-восстановление. Проверка граничного случая',
                    enabled: !_busy,
                    onTap: _clearDeviceToken,
                  ),
                  _ActionTile(
                    icon: Icons.warning_amber,
                    title: 'Отравить auth_token',
                    subtitle:
                    'Следующий запрос получит 401 — тест самовосстановления',
                    enabled: !_busy,
                    onTap: _poisonAuthToken,
                  ),
                  _ActionTile(
                    icon: Icons.vpn_key_off,
                    title: 'Сбросить OAuth-пару',
                    subtitle: 'access_token + refresh_token + expires',
                    enabled: !_busy,
                    onTap: _clearOauthPair,
                  ),
                  _ActionTile(
                    icon: Icons.timer_off,
                    title: 'Сбросить long_token',
                    subtitle: 'Только long_token, остальное на месте',
                    enabled: !_busy,
                    onTap: _clearLongToken,
                  ),
                  _ActionTile(
                    icon: Icons.delete_forever,
                    title: 'Сбросить всю сессию ЭПОС',
                    subtitle: 'Secure storage + память',
                    enabled: !_busy,
                    onTap: _clearWholeEposSession,
                    danger: true,
                  ),
                  _ActionTile(
                    icon: Icons.refresh,
                    title: 'Прогнать refresh прямо сейчас',
                    subtitle: 'Дёрнуть AuthCoordinator.renew() вручную',
                    enabled: !_busy,
                    onTap: _forceRefresh,
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
                    'Сессия + кэш + prefs + SQLite. device_key и тема останутся',
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

/// Строка про device_key. Показываем только факт наличия и длину —
/// сам ключ не палим никак, даже префиксом.
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

/// Сводка по EposSession — что есть, чего нет. Токены НИКОГДА не
/// показываются ни целиком, ни частями: только факт наличия и длина.
/// Длина безопасна и полезна при отладке (32 симв. у auth_token — норма,
/// а 5 симв. — уже сигнал, что что-то не так).
///
/// profile_id исключение: это не секрет, он уходит в заголовке Profile-Id
/// каждого запроса и по нему ничего нельзя подделать.
class _SessionStatusTile extends StatelessWidget {
  final DebugSnapshot? snapshot;

  const _SessionStatusTile({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = snapshot?.epos;

    if (s == null) {
      return ListTile(
        leading: Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
        ),
        title: const Text('Сессия отсутствует'),
        subtitle: const Text('Secure storage пуст'),
      );
    }

    final device = _presence(s.deviceToken);
    final auth = _presence(s.authToken);
    final oauth = s.refreshToken != null
        ? 'есть${s.accessExpiresAt != null ? " (${_expiresLabel(s.accessExpiresAt!)})" : ""}'
        : 'нет';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Текущее состояние',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          _row(
            theme,
            'flow',
            s.deviceToken != null ? 'device-token' : 'legacy OAuth',
          ),
          _row(theme, 'device_token', device),
          _row(theme, 'auth_token', auth),
          _row(theme, 'profile_id', s.profileId),
          _row(theme, 'long_token', _presence(s.longToken)),
          _row(theme, 'OAuth-пара', oauth),
        ],
      ),
    );
  }

  /// Только факт наличия и длина. Никаких префиксов — префикс токена
  /// это тоже часть токена, и он точно так же утекает через скриншоты
  /// и issue-трекеры.
  static String _presence(String? v) {
    if (v == null || v.isEmpty) return '—';
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
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}