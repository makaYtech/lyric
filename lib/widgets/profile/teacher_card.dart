import 'package:flutter/material.dart';

import '../../core/settings/teacher_prefs.dart';
import '../../core/util/names.dart';
import '../../models/teacher.dart';
import '../common/person_avatar.dart';
import '../../core/settings/avatar_storage.dart';

/// Карточка учителя. Компактный вид: аватарка, «Фамилия И. О.» и
/// первый предмет. Раскрытый вид: аватарка, полное ФИО, роли, нагрузка,
/// классрук, предметы, кабинеты, школа.
///
/// Списки предметов/кабинетов по умолчанию показываются до лимита из
/// настроек; «Ещё N» в карточке раскрывает список локально, не трогая
/// настройки. Лимит «Показать всё» отключает кнопку.
class TeacherCard extends StatefulWidget {
  final Teacher teacher;

  const TeacherCard({super.key, required this.teacher});

  @override
  State<TeacherCard> createState() => _TeacherCardState();
}

class _TeacherCardState extends State<TeacherCard> {
  bool _expanded = false;

  // Локальные «раскрыть всё» — живут, пока карточка в дереве.
  bool _subjectsExpanded = false;
  bool _roomsExpanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final teacher = widget.teacher;
    final roles = teacher.displayRoles;

    return ValueListenableBuilder<int>(
      valueListenable: TeacherPrefs.subjectsLimit,
      builder: (context, subjectsLimit, _) => ValueListenableBuilder<int>(
        valueListenable: TeacherPrefs.roomsLimit,
        builder: (context, roomsLimit, _) => ValueListenableBuilder<bool>(
          valueListenable: TeacherPrefs.showOldRooms,
          builder: (context, showOldRooms, _) {
            final visibleRooms = showOldRooms
                ? teacher.rooms
                : teacher.ownRooms;

            return Card(
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: _toggle,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PersonAvatar(
                          fullName: teacher.fullName,
                          radius: 22,
                          avatarKey: AvatarStorage.teacherKey(teacher.id),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _expanded
                                    ? teacher.fullName
                                    : shortTeacherName(teacher.fullName),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!_expanded) ...[
                                const SizedBox(height: 2),
                                Text(
                                  teacher.primarySubject ?? '—',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: dim),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (_expanded) ...[
                                if (roles.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final r in roles)
                                        _RoleBadge(text: r),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 6),
                                _MetaLine(teacher: teacher),
                                if (teacher.managedClasses.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _ClassTeacherLine(
                                    classes: teacher.managedClasses,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _InfoBlock(
                                  label: 'Предметы преподаёт',
                                  allItems: teacher.subjects,
                                  limit: subjectsLimit,
                                  localExpand: _subjectsExpanded,
                                  onToggle: () => setState(
                                        () => _subjectsExpanded =
                                    !_subjectsExpanded,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _InfoBlock(
                                  label: 'Кабинеты',
                                  allItems: visibleRooms
                                      .map((r) => r.display)
                                      .toList(),
                                  limit: roomsLimit,
                                  localExpand: _roomsExpanded,
                                  onToggle: () => setState(
                                        () => _roomsExpanded = !_roomsExpanded,
                                  ),
                                ),
                                if (teacher.buildingName != null) ...[
                                  const SizedBox(height: 12),
                                  _InfoBlock(
                                    label: 'Школа',
                                    allItems: [
                                      teacher.buildingName!,
                                      if (teacher.buildingAddress != null)
                                        teacher.buildingAddress!,
                                    ],
                                    limit: TeacherPrefs.allValue,
                                    localExpand: false,
                                    onToggle: null,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AnimatedRotation(
                            turns: _expanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Строка «Нагрузка · Стаж».
class _MetaLine extends StatelessWidget {
  final Teacher teacher;
  const _MetaLine({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final parts = <String>[
      if (teacher.workload > 0) 'Нагрузка: ${teacher.workload} ч/нед',
      if (teacher.experienceLabel != null) teacher.experienceLabel!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: theme.textTheme.bodySmall?.copyWith(color: dim),
    );
  }
}

/// Строка «Классный руководитель: 8 Н, 11».
class _ClassTeacherLine extends StatelessWidget {
  final List<ManagedClass> classes;
  const _ClassTeacherLine({required this.classes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = classes.map((c) => c.displayName).join(', ');

    return Text(
      'Классный руководитель: $names',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String text;
  const _RoleBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Блок «заголовок + список с маркерами».
class _InfoBlock extends StatelessWidget {
  final String label;
  final List<String> allItems;
  final int limit;
  final bool localExpand;
  final VoidCallback? onToggle;

  const _InfoBlock({
    required this.label,
    required this.allItems,
    required this.limit,
    required this.localExpand,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (allItems.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;

    final limited = limit != TeacherPrefs.allValue &&
        !localExpand &&
        allItems.length > limit;

    final visible = limited ? allItems.sublist(0, limit) : allItems;
    final hidden = allItems.length - visible.length;
    final canCollapse = localExpand &&
        limit != TeacherPrefs.allValue &&
        allItems.length > limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: dim,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < visible.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6),
                  child: Icon(
                    Icons.circle,
                    size: 5,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    visible[i],
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (hidden > 0)
          _ShowMoreLink(
            label: 'Ещё $hidden',
            onTap: onToggle,
          )
        else if (canCollapse)
          _ShowMoreLink(
            label: 'Свернуть',
            onTap: onToggle,
          ),
      ],
    );
  }
}

class _ShowMoreLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _ShowMoreLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.only(left: 11, top: 4, bottom: 2, right: 8),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}