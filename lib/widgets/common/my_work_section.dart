import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/homework_attachment.dart';
import '../../services/attachment_service.dart';
import '../../services/homework_attachments_service.dart';

/// Блок «Моя работа» — файлы, которые ученик сдаёт по этому ДЗ.
/// Самодостаточен: сам тянет актуальный список с сервера, сам
/// прикрепляет и удаляет. Снаружи нужен только id student_homework.
class MyWorkSection extends StatefulWidget {
  final int studentHomeworkId;

  /// Что показать сразу, пока грузится актуальное состояние.
  final List<HomeworkAttachment> initial;

  const MyWorkSection({
    super.key,
    required this.studentHomeworkId,
    this.initial = const [],
  });

  @override
  State<MyWorkSection> createState() => _MyWorkSectionState();
}

class _MyWorkSectionState extends State<MyWorkSection> {
  late List<HomeworkAttachment> _items = widget.initial;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant MyWorkSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentHomeworkId != widget.studentHomeworkId) {
      _items = const [];
      _loading = true;
      _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final list = await HomeworkAttachmentsService.instance.load(
        widget.studentHomeworkId,
      );
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Не удалось загрузить файлы: $e');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _attach() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      _snack(
        'Не удалось прочитать выбранный файл. '
        'Попробуй выбрать его из «Загрузок» или из папки.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final list = await HomeworkAttachmentsService.instance.attach(
        widget.studentHomeworkId,
        filePath: path,
        fileName: picked.name,
      );
      if (!mounted) return;
      setState(() => _items = list);
      _snack('Файл прикреплён');
    } catch (e) {
      _snack('Не удалось прикрепить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detach(HomeworkAttachment a) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: Text(a.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final list = await HomeworkAttachmentsService.instance.detach(
        widget.studentHomeworkId,
        a.id,
      );
      if (!mounted) return;
      setState(() => _items = list);
    } catch (e) {
      _snack('Не удалось удалить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(HomeworkAttachment a) async {
    final res = await AttachmentService.instance.open(a);
    if (!res.ok) _snack(res.error ?? 'Не удалось открыть файл');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Моя работа',
              style: theme.textTheme.labelMedium?.copyWith(
                color: dim,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            if (_loading || _busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_items.isEmpty && !_loading)
          Text(
            'Ничего не прикреплено',
            style: theme.textTheme.bodyMedium?.copyWith(color: dim),
          ),
        for (final a in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _open(a),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (a.displaySize.isNotEmpty)
                              Text(
                                a.displaySize,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: dim,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _busy ? null : () => _detach(a),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Убрать файл',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _busy ? null : _attach,
          icon: const Icon(Icons.attach_file, size: 18),
          label: const Text('Прикрепить файл'),
        ),
      ],
    );
  }
}

/// Шторка «Моя работа» — для случаев, когда места на карточке нет.
Future<void> showMyWorkSheet(
  BuildContext context, {
  required int studentHomeworkId,
  String? subject,
  List<HomeworkAttachment> initial = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subject != null) ...[
              Text(
                subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
            ],
            MyWorkSection(
              studentHomeworkId: studentHomeworkId,
              initial: initial,
            ),
          ],
        ),
      ),
    ),
  );
}
