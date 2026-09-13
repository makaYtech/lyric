import 'package:flutter/material.dart';

import '../../models/teacher.dart';
import 'teacher_card.dart';

/// Блок «Учителя» под карточкой профиля: заголовок, тонкий divider,
/// список маленьких карточек.
///
/// Если учителей нет — возвращает пустой виджет, чтобы не рисовать
/// сиротский заголовок с дивайдером в пустоту.
class TeachersSection extends StatelessWidget {
  final List<Teacher> teachers;

  const TeachersSection({super.key, required this.teachers});

  @override
  Widget build(BuildContext context) {
    if (teachers.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Учителя',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 12),
        for (var i = 0; i < teachers.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          TeacherCard(teacher: teachers[i]),
        ],
      ],
    );
  }
}