import 'package:flutter/material.dart';

import '../core/settings/teacher_prefs.dart';
import '../models/student_profile.dart';
import '../models/teacher.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/profile/profile_card.dart';
import '../widgets/profile/teachers_section.dart';

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
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ProfileCard(
                  profile: profile!,
                  avatarKey: studentAvatarKey,
                ),
                if (visible != null && visible.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  TeachersSection(teachers: visible),
                ],
              ],
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