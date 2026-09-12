import 'package:flutter/material.dart';

import '../core/auth/session_notifier.dart';
import '../core/theme/theme_controller.dart';
import '../services/auth_service.dart';
import '../widgets/auth/reauth_sheet.dart';
import 'grades_view.dart';
import 'home_controller.dart';
import 'profile_view.dart';
import 'reauth_screen.dart';
import 'schedule_view.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final EposTokens tokens;
  final ThemeController themeController;

  const HomeScreen({
    super.key,
    required this.tokens,
    required this.themeController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller;
  final _pageController = PageController();

  final _session = SessionNotifier.instance;
  bool _reauthModalOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = HomeController(
      tokens: widget.tokens,
      onError: _showErrorSnack,
    );
    _session.addListener(_onSessionChanged);
    _controller.init();
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ── Реакция на истёкшую сессию ─────────────────────────────────────────

  void _onSessionChanged() {
    if (!mounted) return;
    if (_session.needsAuth && !_reauthModalOpen) {
      _showReauthSheet();
    }
  }

  Future<void> _showReauthSheet() async {
    if (_reauthModalOpen) return;
    _reauthModalOpen = true;
    try {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => const ReauthSheet(),
      );
      if (confirmed == true) {
        await _runReauth();
      }
    } finally {
      _reauthModalOpen = false;
    }
  }

  Future<void> _runReauth() async {
    final tokens = await Navigator.of(context).push<EposTokens>(
      MaterialPageRoute(builder: (_) => const ReauthScreen()),
    );
    if (tokens == null || !mounted) return;
    _controller.updateTokens(tokens);
    await _controller.refreshCurrentTab();
  }

  // ── Общее ──────────────────────────────────────────────────────────────

  void _showErrorSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  void _onTabSelected(int i) {
    if (i == _controller.tabIndex) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(themeController: widget.themeController),
      ),
    );
  }

  /// Обёртка над onRefresh для вкладок: если нужна переавторизация —
  /// ничего не делаем (иконка в баре уже предлагает войти), иначе
  /// делегируем в контроллер.
  Future<void> _guardedRefresh(Future<void> Function() fn) async {
    if (_session.needsAuth) return;
    await fn();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final title = _controller.currentTitle;

        return Scaffold(
          appBar: AppBar(
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(title, key: ValueKey(_controller.tabIndex)),
            ),
            actions: [
              if (_controller.tabIndex == 1 &&
                  (_controller.years?.isNotEmpty ?? false))
                _YearMenu(controller: _controller),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Настройки',
                onPressed: _openSettings,
              ),
            ],
          ),
          body: PageView(
            controller: _pageController,
            onPageChanged: _controller.setTabIndex,
            children: [
              ProfileView(
                profile: _controller.profile,
                isLoading: _controller.profileLoading,
                error: _controller.profileErrorForView,
                onRefresh: () => _guardedRefresh(_controller.refreshProfile),
              ),
              GradesView(
                grades: _controller.grades,
                isLoading: _controller.gradesLoading,
                error: _controller.gradesErrorForView,
                onRefresh: () => _guardedRefresh(_controller.refreshGrades),
              ),
              ScheduleView(
                schedule: _controller.schedule,
                marks: _controller.marks,
                isLoading: _controller.scheduleLoading,
                error: _controller.scheduleErrorForView,
                weekStart: _controller.weekStart,
                onWeekChanged: _controller.changeWeek,
                onRefresh: () => _guardedRefresh(_controller.refreshSchedule),
              ),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            controller: _controller,
            needsAuth: _session.needsAuth,
            onTabSelected: _onTabSelected,
            onRefreshTap: () {
              if (_session.needsAuth) {
                _showReauthSheet();
              } else {
                _controller.refreshCurrentTab();
              }
            },
          ),
        );
      },
    );
  }
}

/// Нижний бар: табы + кнопка. Когда нужна переавторизация, кнопка
/// превращается в «войти», а не «обновить».
class _BottomBar extends StatelessWidget {
  final HomeController controller;
  final bool needsAuth;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onRefreshTap;

  const _BottomBar({
    required this.controller,
    required this.needsAuth,
    required this.onTabSelected,
    required this.onRefreshTap,
  });

  @override
  Widget build(BuildContext context) {
    final navTheme = NavigationBarTheme.of(context);
    final bg = navTheme.backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainer;

    return Material(
      color: bg,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedIndex: controller.tabIndex,
                onDestinationSelected: onTabSelected,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.person), label: 'Профиль'),
                  NavigationDestination(icon: Icon(Icons.grade), label: 'Оценки'),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_today_outlined),
                    label: 'Расписание',
                  ),
                ],
              ),
            ),
            _TrailingAction(
              needsAuth: needsAuth,
              isLoading: controller.currentLoading,
              onPressed: onRefreshTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailingAction extends StatelessWidget {
  final bool needsAuth;
  final bool isLoading;
  final VoidCallback onPressed;

  const _TrailingAction({
    required this.needsAuth,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget child;
    if (needsAuth) {
      child = IconButton(
        icon: const Icon(Icons.login),
        tooltip: 'Войти заново',
        onPressed: onPressed,
      );
    } else if (isLoading) {
      child = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      child = IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Обновить',
        onPressed: onPressed,
      );
    }

    return SizedBox(
      width: 56,
      height: 80,
      child: Center(
        child: needsAuth
            ? IconTheme.merge(
          data: IconThemeData(color: theme.colorScheme.error),
          child: child,
        )
            : child,
      ),
    );
  }
}

class _YearMenu extends StatelessWidget {
  final HomeController controller;

  const _YearMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.school_outlined),
      tooltip: 'Учебный год',
      initialValue: controller.selectedYearId,
      onSelected: controller.changeYear,
      itemBuilder: (_) => [
        for (final y in controller.years!)
          CheckedPopupMenuItem<int>(
            value: y.id,
            checked: y.id == controller.selectedYearId,
            child: Text(y.name),
          ),
      ],
    );
  }
}