import 'package:flutter/material.dart';

import '../models/student_profile.dart';
import '../widgets/async_state_view.dart';
import '../widgets/profile_card.dart';

/// Чисто отображение — данные и состояние загрузки приходят снаружи
/// (из HomeScreen), сам виджет ничего не грузит и не кэширует.
class ProfileView extends StatelessWidget {
  final StudentProfile? profile;
  final bool isLoading;
  final String? error;

  const ProfileView({
    super.key,
    required this.profile,
    required this.isLoading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return AsyncStateView(
      isLoading: isLoading,
      error: error,
      hasData: profile != null,
      contentBuilder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProfileCard(profile: profile!),
        ],
      ),
    );
  }
}