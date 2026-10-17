import 'package:flutter/material.dart';

import '../../models/homework.dart';
import '../common/attachment_button.dart';
import '../common/my_work_section.dart';
import 'homework_details_sheet.dart';
import '../shell/adaptive_sheet.dart';

class HomeworkCard extends StatelessWidget {
  final Homework homework;

  const HomeworkCard({super.key, required this.homework});

  Future<void> _openDetails(BuildContext context) {
    return showAdaptiveSheet<void>(
      context,
      draggable: true,
      useSafeArea: true,
      initialSize: 0.5,
      minSize: 0.3,
      maxSize: 1.0,
      snapSizes: const [0.5, 1.0],
      builder: (context, scrollController) => HomeworkDetailsSheet(
        homework: homework,
        scrollController: scrollController!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final subject = homework.subjectName ?? 'Предмет';
    final hasAttachment = homework.attachments.isNotEmpty;
    final myCount = homework.myAttachments.length;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхняя строка: предмет (в одну строку с «…») + действия.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _MyWorkButton(homework: homework, count: myCount),
                  if (hasAttachment) ...[
                    const SizedBox(width: 4),
                    AttachmentButton(
                      attachments: homework.attachments,
                      dense: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Дз: ${homework.description}',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (homework.assignedAt != null || homework.dueDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (homework.assignedAt != null)
                      Text(
                        'Задано ${_short(homework.assignedAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: dim),
                      ),
                    const Spacer(),
                    if (homework.dueDate != null)
                      Text(
                        'Сделать до ${_short(homework.dueDate!)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: dim),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _short(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }
}

class _MyWorkButton extends StatelessWidget {
  final Homework homework;
  final int count;

  const _MyWorkButton({required this.homework, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = count > 0;

    return IconButton(
      onPressed: homework.id == 0
          ? null
          : () => showMyWorkSheet(
              context,
              studentHomeworkId: homework.id,
              subject: homework.subjectName,
              initial: homework.myAttachments,
            ),
      tooltip: 'Моя работа',
      icon: Badge(
        isLabelVisible: count > 1,
        label: Text('$count'),
        child: Icon(
          filled ? Icons.attach_file : Icons.attach_file_outlined,
          size: 22,
        ),
      ),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: filled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        foregroundColor: filled
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
