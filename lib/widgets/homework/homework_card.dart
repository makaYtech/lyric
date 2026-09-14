import 'package:flutter/material.dart';

import '../../models/homework.dart';
import '../common/attachment_button.dart';
import 'homework_details_sheet.dart';

class HomeworkCard extends StatelessWidget {
  final Homework homework;

  const HomeworkCard({super.key, required this.homework});

  Future<void> _openDetails(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.5, 1.0],
        expand: false,
        builder: (context, scrollController) => HomeworkDetailsSheet(
          homework: homework,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    final subject = homework.subjectName ?? 'Предмет';
    final hasAttachment = homework.attachments.isNotEmpty;

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
              // Верхняя строка: предмет + кнопка «скачать» в правом углу.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subject,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (hasAttachment) ...[
                    const SizedBox(width: 8),
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
              if (homework.assignedAt != null ||
                  homework.dueDate != null) ...[
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