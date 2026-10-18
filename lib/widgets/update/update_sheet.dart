import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/layout/adaptive.dart';
import '../../services/update/update_service.dart';
import '../shell/adaptive_sheet.dart';

/// Показывает шторку обновления. Возвращает true, если интент установщика
/// ушёл успешно (не факт, что пользователь подтвердил установку — система
/// сама решит); false — если отменил или что-то не получилось.
Future<bool> showUpdateSheet(BuildContext context, UpdateInfo info) async {
  final result = await showAdaptiveSheet<bool>(
    context,
    useSafeArea: true,
    builder: (_, _) => UpdateSheet(info: info),
  );
  return result == true;
}

enum _Phase { prompt, downloading, verifying, installing, failed, done }

class UpdateSheet extends StatefulWidget {
  final UpdateInfo info;

  const UpdateSheet({super.key, required this.info});

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  _Phase _phase = _Phase.prompt;
  double _progress = 0;
  String? _error;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel('sheet closed');
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });

    final token = CancelToken();
    _cancelToken = token;

    final result = await UpdateService.instance.downloadAndVerify(
      widget.info,
      cancelToken: token,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p.clamp(0.0, 1.0));
      },
    );

    if (!mounted) return;
    _cancelToken = null;

    if (result.file == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = result.error ?? 'Не удалось скачать обновление';
      });
      return;
    }

    setState(() => _phase = _Phase.installing);

    final install = await UpdateService.instance.install(result.file!);
    if (!mounted) return;

    if (install.ok) {
      setState(() => _phase = _Phase.done);
      // Даём пользователю увидеть финальное состояние, потом закрываем.
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      setState(() {
        _phase = _Phase.failed;
        _error = install.error ?? 'Не удалось открыть установщик';
      });
    }
  }

  /// Desktop: ставить самим не умеем — открываем страницу загрузки.
  Future<void> _openReleasePage() async {
    final url = UpdateService.instance.releasePageUrl(widget.info);
    bool ok;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Не удалось открыть браузер. Страница загрузки:\n$url';
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('user cancelled');
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildContent(theme),
        ),
      ),
    );
  }

  List<Widget> _buildContent(ThemeData theme) {
    switch (_phase) {
      case _Phase.prompt:
        return _buildPrompt(theme);
      case _Phase.downloading:
        return _buildDownloading(theme);
      case _Phase.verifying:
        return _buildBusy(theme, 'Проверка целостности…');
      case _Phase.installing:
        return _buildBusy(theme, 'Открываем установщик…');
      case _Phase.done:
        return _buildDone(theme);
      case _Phase.failed:
        return _buildFailed(theme);
    }
  }

  // ── Prompt ───────────────────────────────────────────────────────────

  List<Widget> _buildPrompt(ThemeData theme) {
    final dim = theme.colorScheme.onSurfaceVariant;
    return [
      Row(
        children: [
          Icon(
            Icons.system_update_alt,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Доступно обновление',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        AdaptiveLayout.isDesktopOS
            ? 'Версия ${widget.info.version}'
            : 'Версия ${widget.info.version} · ${widget.info.displaySize}',
        style: theme.textTheme.bodyMedium?.copyWith(color: dim),
      ),
      const SizedBox(height: 16),
      const Divider(height: 1),
      const SizedBox(height: 12),
      Text(
        'Что нового',
        style: theme.textTheme.labelMedium?.copyWith(
          color: dim,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 6),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: Text(
            widget.info.changelog.isEmpty
                ? 'Без описания'
                : widget.info.changelog,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Позже'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AdaptiveLayout.isDesktopOS
                ? FilledButton.icon(
                    onPressed: _openReleasePage,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Открыть страницу'),
                  )
                : FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Обновить'),
                  ),
          ),
        ],
      ),
    ];
  }

  // ── Downloading ──────────────────────────────────────────────────────

  List<Widget> _buildDownloading(ThemeData theme) {
    final percent = (_progress * 100).toStringAsFixed(0);
    return [
      Text(
        'Скачивание обновления',
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '$percent% из ${widget.info.displaySize}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _progress == 0 ? null : _progress,
          minHeight: 8,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: _cancelDownload,
              child: const Text('Отменить'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildBusy(ThemeData theme, String message) {
    return [
      Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: theme.textTheme.titleMedium)),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildDone(ThemeData theme) {
    return [
      Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Установщик открыт',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Подтверди установку в системном окне.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildFailed(ThemeData theme) {
    return [
      Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Не удалось установить обновление',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        _error ?? 'Неизвестная ошибка',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Закрыть'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: AdaptiveLayout.isDesktopOS ? _openReleasePage : _start,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Повторить'),
            ),
          ),
        ],
      ),
    ];
  }
}
