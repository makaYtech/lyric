import 'package:flutter/material.dart';

import '../../core/auth/auth_coordinator.dart';
import '../../core/auth/epos_session.dart';
import '../../core/auth/session_refresh_service.dart';
import '../../core/cache/profile_scope.dart';
import '../../core/db/app_database.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/services/epos/account_service.dart';
import '../home/home_screen.dart';
import './child_picker_screen.dart';

/// Определяет роль аккаунта и, если это родитель, выбирает ребёнка,
/// прежде чем открыть главный экран.
class SessionGate extends StatefulWidget {
  final EposSession session;
  final ThemeController themeController;

  const SessionGate({
    super.key,
    required this.session,
    required this.themeController,
  });

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late EposSession _session;
  final _accountService = AccountService();

  bool _busy = true;
  String? _error;
  List<ChildOption>? _children;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    // Gate ходит в сеть до HomeScreen: AuthCoordinator должен знать сессию,
    // иначе первый же 401 не сможет её обновить.
    AuthCoordinator.instance.setSession(_session);
    _start();
  }

  /// После запроса сессия могла обновиться внутри AuthCoordinator.
  void _syncSession() {
    final latest = AuthCoordinator.instance.session;
    if (latest != null) _session = latest;
  }

  Future<void> _start() async {
    final type = _session.accountType;
    final active = _session.activeProfileId;

    if (active != null) {
      await _enterHome(_session, active);
      return;
    }
    if (type == 'student') {
      await _enterHome(_session, null);
      return;
    }
    await _resolve();
  }

  Future<void> _resolve() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
        _children = null;
      });
    }

    try {
      final account = await _accountService.fetch(_session.tokens);
      _syncSession();
      if (!mounted) return;

      // user_id владельца нужен для будущих acl/api/users. При ручном
      // входе его в сессии нет — берём из ответа.
      final ownerId = account.ownerUserId;
      if (ownerId != null && _session.userId != ownerId) {
        _session = _session.copyWith(userId: ownerId);
        await SessionRefreshService.instance.save(_session);
        AuthCoordinator.instance.setSession(_session);
        if (!mounted) return;
      }

      // Пустой ответ — роль не определить, не считаем это «учеником».
      if (account.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Не удалось определить тип аккаунта';
        });
        return;
      }

      if (!account.isParent) {
        final next = _session.copyWith(accountType: 'student');
        await SessionRefreshService.instance.save(next);
        if (!mounted) return;
        await _enterHome(next, null);
        return;
      }

      final ids = account.childrenProfileIds;
      if (ids.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'У аккаунта нет доступных профилей детей';
        });
        return;
      }

      final options = <ChildOption>[];
      for (final id in ids) {
        try {
          final profile = await _accountService.fetchChildProfile(
            _session.tokens,
            id,
          );
          _syncSession();
          if (profile != null) {
            options.add(ChildOption(profileId: id, profile: profile));
          }
        } catch (_) {
          _syncSession();
        }
      }
      if (!mounted) return;

      if (options.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Не удалось загрузить профили детей';
        });
        return;
      }

      if (options.length == 1) {
        await _select(options.first);
        return;
      }

      setState(() {
        _busy = false;
        _children = options;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Не удалось определить аккаунт: $e';
      });
    }
  }

  Future<void> _select(ChildOption child) async {
    _syncSession();
    final next = _session.copyWith(
      accountType: 'parent',
      activeProfileId: '${child.profileId}',
    );
    await SessionRefreshService.instance.save(next);
    if (!mounted) return;
    _session = next;
    await _enterHome(next, '${child.profileId}');
  }

  Future<void> _enterHome(EposSession session, String? activeProfileId) async {
    try {
      final profileId = activeProfileId ?? session.profileId;
      ProfileScope.set(profileId);
      if (activeProfileId == null) {
        await ProfileScope.migrateLegacyData();
      }
      await AppDatabase.instance.switchProfile(
        profileId,
        migrateLegacy: activeProfileId == null,
      );
      if (!mounted) return;

      AuthCoordinator.instance.setSession(session);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            session: session,
            themeController: widget.themeController,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _children = null;
        _error = 'Не удалось открыть данные: $e';
      });
    }
  }

  /// Сеть недоступна на первом запуске после обновления — не блокируем
  /// офлайн-режим. Роль не сохраняем, при следующем старте проверим снова.
  Future<void> _continueWithoutCheck() async {
    _syncSession();
    await _enterHome(_session, _session.activeProfileId);
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children != null) {
      return _withAuthHost(
        ChildPickerScreen(children: children, onPicked: _select),
      );
    }

    return _withAuthHost(
      Scaffold(
        body: Center(
          child: _busy
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error ?? 'Не удалось загрузить аккаунт',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _resolve,
                          child: const Text('Повторить'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _continueWithoutCheck,
                          child: const Text('Продолжить без проверки'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// Legacy-сессиям нужен скрытый WebView для refresh: он живёт в
  /// HomeScreen, но первый запрос делает ещё gate.
  Widget _withAuthHost(Widget child) {
    if (widget.session.deviceToken != null || !AdaptiveLayout.hasWebView) {
      return child;
    }
    return Stack(
      children: [
        Positioned.fill(child: child),
        const AuthWebViewHost(),
      ],
    );
  }
}
