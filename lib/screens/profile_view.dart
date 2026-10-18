import 'package:flutter/material.dart';

import '../core/layout/adaptive.dart';
import '../core/settings/teacher_prefs.dart';
import '../models/student_profile.dart';
import '../models/teacher.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/common/masonry_columns.dart';
import '../widgets/profile/profile_card.dart';
import '../widgets/profile/teacher_card.dart';
import '../widgets/profile/teachers_section.dart';
import '../widgets/common/stable_layout_builder.dart';

class ProfileView extends StatelessWidget {
  final StudentProfile? profile;
  final List<Teacher>? teachers;

  /// id учителей, которые ведут у текущего ученика. Если пусто —
  /// фильтр «только мои учителя» не даст ничего показать.
  final Set<int>? studentTeacherIds;

  /// Ключ локальной аватарки ученика. Если null — тап по аватарке
  /// не открывает picker.
  final String? studentAvatarKey;

  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;

  const ProfileView({
    super.key,
    required this.profile,
    this.teachers,
    this.studentTeacherIds,
    this.studentAvatarKey,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: AsyncStateView(
        isLoading: isLoading,
        error: error,
        hasData: profile != null,
        contentBuilder: (context) => ValueListenableBuilder<bool>(
          valueListenable: TeacherPrefs.onlyStudentTeachers,
          builder: (context, onlyMine, _) {
            final visible = _visibleTeachers(onlyMine);
            // Ключ = число колонок учителей (0 — узкий режим): при ресайзе
            // дерево пересобирается только когда оно реально меняется.
            return StableLayoutBuilder<int>(
              keyOf: (c) => AdaptiveLayout.wideContent(c.maxWidth)
                  ? ((c.maxWidth - _WideProfileState._leftWidth - 33) / 340)
                        .floor()
                        .clamp(1, 3)
                  : 0,
              builder: (context, constraints, columns) {
                if (columns > 0) {
                  return _WideProfile(
                    profile: profile!,
                    avatarKey: studentAvatarKey,
                    teachers: visible,
                    columns: columns,
                  );
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    ProfileCard(profile: profile!, avatarKey: studentAvatarKey),
                    if (visible != null && visible.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      TeachersSection(teachers: visible),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Teacher>? _visibleTeachers(bool onlyMine) {
    final list = teachers;
    if (list == null || list.isEmpty) return list;
    if (!onlyMine) return list;
    final ids = studentTeacherIds;
    if (ids == null || ids.isEmpty) return const [];
    return list.where((t) => ids.contains(t.id)).toList();
  }
}

/// Профиль на широком экране: слева карточка ученика (фиксированной ширины,
/// со своей прокруткой), справа учителя «кладкой» из нескольких колонок.
/// Каждая карточка учителя раскрывается независимо, поэтому колонки разной
/// высоты — как раз то, что нужно.
class _WideProfile extends StatefulWidget {
  final StudentProfile profile;
  final String? avatarKey;
  final List<Teacher>? teachers;
  final int columns;

  const _WideProfile({
    required this.profile,
    required this.avatarKey,
    required this.teachers,
    required this.columns,
  });

  @override
  State<_WideProfile> createState() => _WideProfileState();
}

class _WideProfileState extends State<_WideProfile> {
  static const _leftWidth = 400.0;

  final _leftScroll = ScrollController();
  final _rightScroll = ScrollController();

  @override
  void dispose() {
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teachers = widget.teachers ?? const <Teacher>[];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _leftWidth,
          child: SingleChildScrollView(
            controller: _leftScroll,
            padding: const EdgeInsets.all(16),
            child: ProfileCard(
              profile: widget.profile,
              avatarKey: widget.avatarKey,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: teachers.isEmpty
              ? Center(
                  child: Text(
                    'Нет данных об учителях',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _rightScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _rightScroll,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Учителя · ${teachers.length}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                        MasonryColumns(
                          columns: widget.columns,
                          spacing: 10,
                          children: [
                            for (final t in teachers) TeacherCard(teacher: t),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
