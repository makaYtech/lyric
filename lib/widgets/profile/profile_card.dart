import 'package:flutter/material.dart';

import '../../core/util/names.dart';
import '../../models/student_profile.dart';
import '../common/info_tile.dart';
import 'schools_tile.dart';

class ProfileCard extends StatelessWidget {
  final StudentProfile profile;

  const ProfileCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(profile: profile),
          const Divider(height: 1),
          _Body(profile: profile),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final StudentProfile profile;

  const _Header({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              initials(profile.userName),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.userName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (profile.className != '—') ...[
                  const SizedBox(height: 4),
                  Text(
                    profile.className,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final StudentProfile profile;

  const _Body({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoTile(label: 'Класс', value: profile.className),
          const SizedBox(height: 16),
          InfoTile(label: 'Профиль обучения', value: profile.curriculumName),
          const SizedBox(height: 16),
          SchoolsTile(schools: profile.schoolNames),
        ],
      ),
    );
  }
}