import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/auth/auth_config.dart';
import '../core/auth/auth_coordinator.dart';
import '../core/auth/epos_session.dart';
import '../core/auth/session_notifier.dart';
import '../core/layout/adaptive.dart';
import '../core/settings/homework_prefs.dart';
import '../core/settings/layout_prefs.dart';
import '../core/settings/avatar_storage.dart';
import '../core/theme/theme_controller.dart';
import '../widgets/auth/reauth_sheet.dart';
import '../widgets/shell/app_side_bar.dart';
import 'device_reauth_screen.dart';
import 'grades_view.dart';
import 'home_controller.dart';
import 'homework_view.dart';
import 'profile_view.dart';
import 'reauth_screen.dart';
import 'schedule_view.dart';
import 'settings_screen.dart';
import '../services/attachment_service.dart';
import '../core/settings/update_prefs.dart';
import '../services/update/update_service.dart';
import '../widgets/update/update_sheet.dart';
import '../widgets/shell/adaptive_sheet.dart';

class HomeScreen extends StatefulWidget {
  final EposSession session;
  final ThemeController themeController;

  const HomeScreen({
    super.key,
    required this.session,
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

  /// true — сейчас идёт анимация переключения, начатая тапом по табу.
  /// Пока true, onPageChanged игнорируется (иначе промежуточные страницы
  /// перебивают финальный setTabIndex, и бар залипает на неверном табе).
  bool _animatingToTab = false;

  /// Монотонный счётчик, отменяет предыдущую анимацию при быстрых тычках.
  int _animationId = 0;

  @override
  void initState() {
    super.initState();

    _session.reset();
    AuthCoordinator.instance.setSession(widget.session);

    _controller = HomeController(
      session: widget.session,
      onError: _showErrorSnack,
    );
    _session.addListener(_onSessionChanged);
    _controller.init();
    AttachmentService.instance.setSession(widget.session);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), _checkUpdatesOnStart);
    });
  }

  Future<void> _checkUpdatesOnStart() async {
    if (!mounted) return;
    final check = await UpdateService.instance.check(UpdatePrefs.channel.value);
    if (!mounted) return;
    if (check.result != UpdateCheckResult.available) return;

    final info = check.info;
    if (info == null) return;

    final started = await showUpdateSheet(context, info);
    if (!mounted) return;

    if (!started) {
      _showErrorSnack('Обновиться можно в меню настроек', errorStyle: false);
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

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
      final confirmed = await showAdaptiveSheet<bool>(
        context,
        dismissible: false,
        builder: (_, _) => const ReauthSheet(),
      );
      if (confirmed == true) {
        await _runReauth();
      }
    } finally {
      _reauthModalOpen = false;
    }
  }

  Future<void> _runReauth() async {
    final useDevice = AuthConfig.useDeviceTokenFlow.value;

    final session = await Navigator.of(context).push<EposSession>(
      MaterialPageRoute(
        builder: (_) =>
            useDevice ? const DeviceReauthScreen() : const ReauthScreen(),
      ),
    );
    if (!mounted) return;
    if (session == null) {
      _showErrorSnack(
        'Не удалось войти заново. Работаем с сохранёнными данными.',
      );
      return;
    }
    await _controller.updateSession(session);
    AttachmentService.instance.setSession(session);
    await _controller.refreshAll();
  }

  void _showErrorSnack(String message, {bool errorStyle = true}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2500),
        // Широкий экран: нижнего бара нет, снэкбар — компактный, а не на всю ширину.
        width: AdaptiveLayout.useSideBar(MediaQuery.sizeOf(context).width)
            ? 420
            : null,
        margin: AdaptiveLayout.useSideBar(MediaQuery.sizeOf(context).width)
            ? null
            : const EdgeInsets.fromLTRB(16, 0, 16, 96),
        backgroundColor: errorStyle
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  /// Переключение таба. Индекс выставляется в контроллере ТОЛЬКО в конце
  /// анимации — чтобы промежуточные страницы (в т.ч. расписание) не
  /// перебивали финальный выбор.
  void _onTabSelected(int i) {
    if (i == _controller.tabIndex) return;

    // Широкий экран: страницы не «листаются», просто переключаемся.
    if (AdaptiveLayout.useSideBar(MediaQuery.sizeOf(context).width)) {
      _animationId++;
      _animatingToTab = false;
      _pageController.jumpToPage(i);
      _controller.setTabIndex(i);
      return;
    }

    final myId = ++_animationId;
    _animatingToTab = true;

    _pageController
        .animateToPage(
          i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .whenComplete(() {
          if (!mounted) return;
          // Анимацию перебили более свежим тапом — не трогаем таб-индекс.
          if (myId != _animationId) return;
          _animatingToTab = false;
          _controller.setTabIndex(i);
        });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          themeController: widget.themeController,
          studentAvatarKey: AvatarStorage.studentKey(
            _controller.tokens.profileId,
          ),
          teachers: _controller.teachers,
        ),
      ),
    );
  }

  Future<void> _guardedRefresh(Future<void> Function() fn) => fn();

  @override
  Widget build(BuildContext context) {
    final needsHiddenWebView = Listenable.merge([
      AuthConfig.useDeviceTokenFlow,
      _controller,
    ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = AdaptiveLayout.useSideBar(constraints.maxWidth);

        final scaffold = Scaffold(
          appBar: _HomeAppBar(
            controller: _controller,
            onOpenSettings: _openSettings,
            // На широком экране настройки уходят в боковую панель.
            showSettings: !wide,
          ),
          body: _buildPages(wide),
          bottomNavigationBar: wide ? null : _buildBottomBar(),
        );

        return CallbackShortcuts(
          bindings: _globalBindings,
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                wide ? _wrapWithSideBar(scaffold) : scaffold,
                ListenableBuilder(
                  listenable: needsHiddenWebView,
                  builder: (context, _) {
                    // На desktop webview_flutter не реализован — не монтируем.
                    if (!AdaptiveLayout.webViewSupported) {
                      return const SizedBox.shrink();
                    }
                    final useDevice = AuthConfig.useDeviceTokenFlow.value;
                    final session = _controller.session;
                    final needsWebView =
                        !useDevice || session.deviceToken == null;
                    if (!needsWebView) return const SizedBox.shrink();
                    return const AuthWebViewHost();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Горячие клавиши уровня всего приложения. Вкладки (ДЗ и т.д.) добавляют
  /// свои, например ←/→ для переключения дня.
  Map<ShortcutActivator, VoidCallback> get _globalBindings => {
    const SingleActivator(LogicalKeyboardKey.f5): _onRefreshTap,
    const SingleActivator(LogicalKeyboardKey.keyR, control: true):
        _onRefreshTap,
    const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
        _onTabSelected(0),
    const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
        _onTabSelected(1),
    const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
        _onTabSelected(2),
    const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
        _onTabSelected(3),
    const SingleActivator(LogicalKeyboardKey.comma, control: true):
        _openSettings,
  };

  void _onRefreshTap() {
    if (_session.needsAuth) {
      _showReauthSheet();
    } else {
      _controller.refreshAll();
    }
  }

  Widget _buildBottomBar() {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _session]),
      builder: (context, _) => _BottomBar(
        controller: _controller,
        needsAuth: _session.needsAuth,
        onTabSelected: _onTabSelected,
        onRefreshTap: _onRefreshTap,
      ),
    );
  }

  /// Вкладки в панели. «Профиль» (tabIndex 0) сюда не входит: он открывается
  /// нажатием на пользователя внизу панели. Поэтому индекс в панели =
  /// tabIndex − 1.
  static const _sideBarItems = [
    SideBarItem(
      icon: Icons.grade_outlined,
      selectedIcon: Icons.grade,
      label: 'Оценки',
    ),
    SideBarItem(
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      label: 'Расписание',
    ),
    SideBarItem(
      icon: Icons.book_outlined,
      selectedIcon: Icons.book,
      label: 'ДЗ',
    ),
  ];

  /// Боковая панель + контент. Сторона и «раскрытость» — из LayoutPrefs.
  Widget _wrapWithSideBar(Widget content) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LayoutPrefs.sideBarOnRight,
        LayoutPrefs.sideBarExpanded,
        HomeworkPrefs.groupByDue,
        _controller,
        _session,
      ]),
      builder: (context, _) {
        final onRight = LayoutPrefs.sideBarOnRight.value;
        final expanded = LayoutPrefs.sideBarExpanded.value;
        final profile = _controller.profile;

        final bar = AppSideBar(
          items: _sideBarItems,
          selectedIndex: _controller.tabIndex - 1,
          onSelected: (i) => _onTabSelected(i + 1),
          userSelected: _controller.tabIndex == 0,
          onUserTap: () => _onTabSelected(0),
          expanded: expanded,
          onToggleExpanded: AdaptiveLayout.canToggleSideBar
              ? () => LayoutPrefs.setSideBarExpanded(!expanded)
              : null,
          onRight: onRight,
          needsAuth: _session.needsAuth,
          isLoading: _controller.anyLoading,
          onRefresh: _onRefreshTap,
          onOpenSettings: _openSettings,
          toggles: [
            // Бывший переключатель «Ещё немного — и кранты» из шапок ДЗ и
            // расписания: на широком экране он живёт здесь.
            SideBarToggle(
              icon: Icons.event_busy_outlined,
              label: HomeworkPrefs.groupByDue.value
                  ? 'ДЗ по сроку сдачи (вкл)'
                  : 'ДЗ по сроку сдачи',
              active: HomeworkPrefs.groupByDue.value,
              onTap: () =>
                  HomeworkPrefs.setGroupByDue(!HomeworkPrefs.groupByDue.value),
            ),
          ],
          userName: profile?.userName ?? 'Профиль',
          userSubtitle: profile?.className,
          userAvatarKey: AvatarStorage.studentKey(_controller.tokens.profileId),
          userActions: [
            if (_session.needsAuth)
              SideBarUserAction(
                icon: Icons.login,
                label: 'Войти заново',
                onTap: _showReauthSheet,
              ),
            // Для родителя сюда встанет переключатель детей.
          ],
        );

        // Контент отступает на ИТОГОВУЮ ширину панели сразу, а сама панель
        // плавно растёт поверх. Если анимировать ширину в Row, дневник,
        // оценки и колонки ДЗ пересчитывались бы на каждом кадре анимации —
        // это и давало лаги при раскрытии меню.
        final barWidth = expanded
            ? AppSideBar.expandedWidth
            : AppSideBar.collapsedWidth;
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            children: [
              Positioned.fill(
                left: onRight ? 0 : barWidth,
                right: onRight ? barWidth : 0,
                child: content,
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: onRight ? null : 0,
                right: onRight ? 0 : null,
                child: bar,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPages(bool wide) {
    return PageView(
      controller: _pageController,
      // Мышь/тачпад не должны листать вкладки горизонтальным скроллом.
      physics: wide ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (i) {
        // Свайп пользователя: обновляем таб сразу. Тап-инициированные
        // переключения сюда не доходят — там _animatingToTab == true.
        if (_animatingToTab) return;
        _controller.setTabIndex(i);
      },
      children: [
        ListenableBuilder(
          listenable: _controller.profileTick,
          builder: (context, _) => ProfileView(
            profile: _controller.profile,
            teachers: _controller.teachers,
            studentTeacherIds: _controller.studentTeacherIds,
            studentAvatarKey: AvatarStorage.studentKey(
              _controller.tokens.profileId,
            ),
            isLoading: _controller.profileLoading,
            error: _controller.profileErrorForView,
            onRefresh: () => _guardedRefresh(_controller.refreshProfile),
          ),
        ),
        ListenableBuilder(
          listenable: _controller.gradesTick,
          builder: (context, _) => GradesView(
            grades: _controller.grades,
            isLoading: _controller.gradesLoading,
            error: _controller.gradesErrorForView,
            onRefresh: () => _guardedRefresh(_controller.refreshGrades),
          ),
        ),
        ListenableBuilder(
          listenable: _controller.scheduleTick,
          builder: (context, _) => ScheduleView(
            schedule: _controller.schedule,
            marks: _controller.marks,
            grades: _controller.grades,
            attendances: _controller.attendances,
            bells: _controller.bells,
            isActive: _controller.tabIndex == 2,
            autoScrollAlreadyDone: _controller.scheduleAutoScrolledOnce,
            onAutoScrollDone: _controller.markScheduleAutoScrolled,
            isLoading: _controller.scheduleLoading,
            error: _controller.scheduleErrorForView,
            weekStart: _controller.weekStart,
            onWeekChanged: _controller.changeWeek,
            onRefresh: () => _guardedRefresh(_controller.refreshSchedule),
            onDeleteLessons: (date, ids) =>
                _controller.deleteScheduleLessons(date: date, lessonIds: ids),
            onMoveLessons: (date, moves) =>
                _controller.moveScheduleLessons(date: date, moves: moves),
            onRevertOverrideIds: (ids) =>
                _controller.revertScheduleOverrides(ids),
            onRevertOverride: (id) => _controller.revertScheduleOverride(id),
            onRevertWeek: () => _controller.revertWeekOverrides(),
            onLoadWeekOverrides: () => _controller.loadWeekOverrides(),
            onLoadWeekRawLessons: () => _controller.loadWeekRawLessons(),
            daysWithOverrides: _controller.daysWithOverrides,
            changedLessonIds: _controller.changedLessonIds,
            onBreakPair: (date, primaryId, secondaryId) =>
                _controller.breakSchedulePair(
                  date: date,
                  primaryId: primaryId,
                  secondaryId: secondaryId,
                ),
            onMakePair: (date, primaryId, secondaryId) =>
                _controller.makeSchedulePair(
                  date: date,
                  primaryId: primaryId,
                  secondaryId: secondaryId,
                ),
            onReorderLessons: (date, orig, next) =>
                _controller.reorderScheduleDay(
                  date: date,
                  originalOrder: orig,
                  newOrder: next,
                ),
          ),
        ),
        ListenableBuilder(
          listenable: _controller.homeworksTick,
          builder: (context, _) => HomeworkView(
            homeworks: _controller.homeworks,
            isLoading: _controller.homeworksLoading,
            error: _controller.homeworksErrorForView,
            isActive: _controller.tabIndex == 3,
            onRefresh: () => _guardedRefresh(_controller.refreshHomeworks),
          ),
        ),
      ],
    );
  }
}

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final HomeController controller;
  final VoidCallback onOpenSettings;
  final bool showSettings;

  const _HomeAppBar({
    required this.controller,
    required this.onOpenSettings,
    this.showSettings = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            controller.currentTitle,
            key: ValueKey(controller.tabIndex),
          ),
        ),
        actions: [
          if ((controller.tabIndex == 1 || controller.tabIndex == 3) &&
              (controller.years?.isNotEmpty ?? false))
            _YearMenu(controller: controller),
          if (showSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Настройки',
              onPressed: onOpenSettings,
            ),
        ],
      ),
    );
  }
}

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
    final bg =
        navTheme.backgroundColor ??
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
                  NavigationDestination(
                    icon: Icon(Icons.person),
                    label: 'Профиль',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grade),
                    label: 'Оценки',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_today_outlined),
                    label: 'Расписание',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.book_outlined),
                    label: 'ДЗ',
                  ),
                ],
              ),
            ),
            _TrailingAction(
              needsAuth: needsAuth,
              isLoading: controller.anyLoading,
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
        tooltip: 'Обновить всё',
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
