import 'package:flutter/material.dart';

import '../models/student_profile.dart';
import '../widgets/common/async_state_view.dart';
import '../widgets/profile/profile_card.dart';

/// Чисто отображение — данные и состояние загрузки приходят снаружи
/// (из HomeController), сам виджет ничего не грузит и не кэширует.
/// Pull-to-refresh дёргает [onRefresh] — обновляется только эта вкладка.
class ProfileView extends StatelessWidget {
  final StudentProfile? profile;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;

  const ProfileView({
    super.key,
    required this.profile,
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
        contentBuilder: (context) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            ProfileCard(profile: profile!),
          ],
        ),
      ),
    );
  }
}