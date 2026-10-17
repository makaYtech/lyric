import 'package:flutter/material.dart';

import '../common/person_avatar.dart';

/// Вкладка боковой панели.
class SideBarItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const SideBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Пункт меню, которое открывается по нажатию на пользователя внизу панели.
/// Список передаётся снаружи: для родителя сюда же встанет переключатель
/// детей, а сам виджет менять не придётся.
class SideBarUserAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SideBarUserAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// Боковая панель для широких окон.
///
/// Сверху вниз: кнопка раскрытия (если [onToggleExpanded] != null),
/// вкладки, пустое место, обновление, настройки, пользователь.
/// Ширина анимируется между [collapsedWidth] и [expandedWidth].
class AppSideBar extends StatelessWidget {
  static const double collapsedWidth = 72;
  static const double expandedWidth = 248;

  /// Подписи показываем только когда панель реально широкая,
  /// иначе в процессе анимации Row ругался бы на overflow.
  static const double _labelThreshold = 170;

  final List<SideBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  final bool expanded;

  /// null — кнопку раскрытия не показываем (Android).
  final VoidCallback? onToggleExpanded;

  /// Панель справа: граница рисуется с левой стороны, и наоборот.
  final bool onRight;

  final bool needsAuth;
  final bool isLoading;
  final VoidCallback onRefresh;

  final VoidCallback onOpenSettings;

  final String userName;
  final String? userSubtitle;
  final String? userAvatarKey;
  final List<SideBarUserAction> userActions;

  const AppSideBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRight,
    required this.needsAuth,
    required this.isLoading,
    required this.onRefresh,
    required this.onOpenSettings,
    required this.userName,
    required this.userSubtitle,
    required this.userAvatarKey,
    required this.userActions,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final edge = BorderSide(color: cs.outlineVariant);

    return Material(
      color: cs.surfaceContainer,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: expanded ? expandedWidth : collapsedWidth,
        // foreground — чтобы граница не съедала ширину и иконки не уезжали.
        foregroundDecoration: BoxDecoration(
          border: onRight ? Border(left: edge) : Border(right: edge),
        ),
        child: SafeArea(
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, box) {
                final showLabels = box.maxWidth > _labelThreshold;
                return Column(
                  children: [
                    if (onToggleExpanded != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: IconButton(
                            icon: Icon(expanded ? Icons.menu_open : Icons.menu),
                            tooltip: expanded ? 'Свернуть' : 'Развернуть',
                            onPressed: onToggleExpanded,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    for (var i = 0; i < items.length; i++)
                      _Tile(
                        icon: Icon(
                          i == selectedIndex
                              ? items[i].selectedIcon
                              : items[i].icon,
                        ),
                        label: items[i].label,
                        selected: i == selectedIndex,
                        showLabel: showLabels,
                        onTap: () => onSelected(i),
                      ),
                    const Spacer(),
                    _buildRefresh(cs, showLabels),
                    _Tile(
                      icon: const Icon(Icons.settings_outlined),
                      label: 'Настройки (Ctrl+,)',
                      showLabel: showLabels,
                      onTap: onOpenSettings,
                    ),
                    const SizedBox(height: 4),
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: cs.outlineVariant,
                    ),
                    _buildUser(context, showLabels),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefresh(ColorScheme cs, bool showLabels) {
    if (needsAuth) {
      return _Tile(
        icon: const Icon(Icons.login),
        label: 'Войти заново',
        color: cs.error,
        showLabel: showLabels,
        onTap: onRefresh,
      );
    }
    if (isLoading) {
      return _Tile(
        icon: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: 'Обновляется…',
        showLabel: showLabels,
        // Во время загрузки повторный тап ничего не делает.
        onTap: null,
      );
    }
    return _Tile(
      icon: const Icon(Icons.refresh),
      label: 'Обновить (F5)',
      showLabel: showLabels,
      onTap: onRefresh,
    );
  }

  Widget _buildUser(BuildContext context, bool showLabels) {
    final theme = Theme.of(context);
    final content = Padding(
      // 20 = 36 (центр иконок) − 16 (радиус аватара).
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          PersonAvatar(
            fullName: userName,
            radius: 16,
            avatarKey: userAvatarKey,
          ),
          if (showLabels) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                  if (userSubtitle != null)
                    Text(
                      userSubtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (userActions.isEmpty) return content;

    return PopupMenuButton<int>(
      tooltip: userName,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      onSelected: (i) => userActions[i].onTap(),
      itemBuilder: (_) => [
        for (var i = 0; i < userActions.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(userActions[i].icon, size: 20),
                const SizedBox(width: 12),
                Text(userActions[i].label),
              ],
            ),
          ),
      ],
      child: content,
    );
  }
}

class _Tile extends StatelessWidget {
  final Widget icon;
  final String label;
  final bool selected;
  final bool showLabel;
  final Color? color;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
    this.selected = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fg = selected
        ? cs.onSecondaryContainer
        : (color ?? cs.onSurfaceVariant);

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: fg, size: 24),
                    child: SizedBox(width: 24, child: Center(child: icon)),
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: fg),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Когда подписей нет — подсказка при наведении вместо них.
    return showLabel ? tile : Tooltip(message: label, child: tile);
  }
}
