import 'package:flutter/material.dart';

import '../../models/homework.dart';
import '../common/attachment_button.dart';
import '../common/my_work_section.dart';

/// Нижняя шторка по тапу на карточку ДЗ. Высоту контролирует
/// DraggableScrollableSheet снаружи — сюда приходит его scrollController,
/// чтобы жест «потянуть вверх» работал на всём содержимом.
class HomeworkDetailsSheet extends StatelessWidget {
  final Homework homework;
  final ScrollController? scrollController;

  const HomeworkDetailsSheet({
    super.key,
    required this.homework,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final subject = homework.subjectName ?? 'Предмет';
    final hasTeacher =
        homework.teacherName != null && homework.teacherName!.isNotEmpty;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis
            ),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (homework.assignedAt != null)
                  Text(
                    'Задано ${_fmt(homework.assignedAt!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: dim),
                  )
                else
                  const SizedBox.shrink(),
                if (hasTeacher)
                  Text(
                    homework.teacherName!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: dim),
                  ),
              ],
            ),

            if (homework.dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Сделать до ${_fmt(homework.dueDate!)}',
                style: theme.textTheme.bodyMedium?.copyWith(color: dim),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            Text(
              'Дз:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: dim,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              homework.description.isEmpty ? 'не задано' : homework.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),

            if (homework.attachments.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Файлы',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: dim,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final a in homework.attachments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AttachmentButton(
                        attachments: [a],
                        label: a.name,
                      ),
                    ),
                ],
              ),
            ],
            if (homework.id != 0) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              MyWorkSection(
                studentHomeworkId: homework.id,
                initial: homework.myAttachments,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${two(d.year)}';
  }
}