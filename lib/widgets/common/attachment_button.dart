import 'package:flutter/material.dart';

import '../../models/homework_attachment.dart';
import '../../services/attachment_service.dart';

/// Кнопка «файл ДЗ». Одна на оба места:
///  - dense (в карточке ДЗ)  — круглая IconButton с иконкой download;
///  - full (в модалках)      — OutlinedButton с именем файла.
///
/// По тапу: скачивает файл во временную папку (с прогрессом прямо
/// в кнопке) и открывает системным приложением через OpenFilex.
/// Если файлов несколько — сначала показывает шторку выбора.
class AttachmentButton extends StatefulWidget {
  final List<HomeworkAttachment> attachments;
  final bool dense;
  final String? label;

  const AttachmentButton({
    super.key,
    required this.attachments,
    this.dense = false,
    this.label,
  });

  @override
  State<AttachmentButton> createState() => _AttachmentButtonState();
}

class _AttachmentButtonState extends State<AttachmentButton> {
  bool _busy = false;
  double _progress = 0;

  Future<void> _onTap() async {
    if (_busy) return;
    final list = widget.attachments;
    if (list.isEmpty) return;

    final target =
    list.length == 1 ? list.first : await _pick(context, list);
    if (target == null || !mounted) return;

    setState(() {
      _busy = true;
      _progress = 0;
    });

    final result = await AttachmentService.instance.open(
      target,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Не удалось открыть файл'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<HomeworkAttachment?> _pick(
      BuildContext context,
      List<HomeworkAttachment> list,
      ) {
    final theme = Theme.of(context);
    return showModalBottomSheet<HomeworkAttachment>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Файлы',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final a in list)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(a.name),
                subtitle: a.displaySize.isEmpty ? null : Text(a.displaySize),
                onTap: () => Navigator.of(context).pop(a),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.attachments.length;
    if (count == 0) return const SizedBox.shrink();

    final spinner = SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        value: _progress == 0 ? null : _progress,
      ),
    );

    if (widget.dense) {
      return IconButton(
        onPressed: _busy ? null : _onTap,
        tooltip: 'Скачать файл',
        icon: _busy
            ? spinner
            : Badge(
          isLabelVisible: count > 1,
          label: Text('$count'),
          child: const Icon(Icons.download_rounded, size: 22),
        ),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
        ),
      );
    }

    final labelText = widget.label ??
        (count == 1 ? 'Скачать файл' : 'Файлы ($count)');

    return OutlinedButton.icon(
      onPressed: _busy ? null : _onTap,
      icon: _busy
          ? spinner
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(labelText, overflow: TextOverflow.ellipsis),
    );
  }
}