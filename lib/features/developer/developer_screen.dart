import 'package:flutter/material.dart';

import '../../core/auth/auth_config.dart';
import '../../core/debug/debug_tools.dart';
import '../../core/theme/theme_controller.dart';
import '../auth/login_screen.dart';

part './developer_screen_auth.dart';
part './developer_screen_tools.dart';
part './developer_screen_widgets.dart';

/// Экран «Для разработчика». Доступен только через SettingsScreen →
/// «Для разработчика» → предупреждение → OK.
class DeveloperScreen extends StatefulWidget {
  final ThemeController themeController;

  const DeveloperScreen({super.key, required this.themeController});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

/// Цель модалки «Отравить…».
class _PoisonTarget {
  final String name;
  final bool isDeviceToken;
  const _PoisonTarget({required this.name, this.isDeviceToken = false});
}

/// Цель модалки «Сбросить…».
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
