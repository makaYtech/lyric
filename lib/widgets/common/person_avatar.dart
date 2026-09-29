import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/settings/avatar_storage.dart';
import '../../core/util/names.dart';

/// Круглая аватарка. Путь к картинке читается синхронно из
/// [AvatarStorage.cachedPath] внутри [ValueListenableBuilder] —
/// как только AvatarStorage отдаст путь (или он там уже есть),
/// виджет сам перерисуется. Никаких ручных setState из async-цепочки,
/// из-за которых была гонка на первом старте.
class PersonAvatar extends StatefulWidget {
  final String fullName;
  final double radius;
  final String? avatarKey;
  final String? photoUrl;

  const PersonAvatar({
    super.key,
    required this.fullName,
    this.radius = 24,
    this.avatarKey,
    this.photoUrl,
  });

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant PersonAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarKey != widget.avatarKey) {
      _ensureLoaded();
    }
  }

  /// Триггерит загрузку из prefs. Сам ничего не делает с UI — за это
  /// отвечает ValueListenableBuilder ниже. Если ключ уже в памяти,
  /// вызов дешёвый и ничего не произойдёт.
  void _ensureLoaded() {
    final key = widget.avatarKey;
    if (key == null) return;
    if (AvatarStorage.isLoaded(key)) return;
    AvatarStorage.path(key);
  }

  Future<void> _pickImage() async {
    final key = widget.avatarKey;
    if (key == null || _loading) return;
    setState(() => _loading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      // Ждём, пока файл точно дописан.
      if (!await _waitForFile(picked.path)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать выбранный файл')),
        );
        return;
      }

      await FileImage(File(picked.path)).evict();
      if (mounted) {
        await precacheImage(FileImage(File(picked.path)), context);
      }
      await AvatarStorage.savePath(key, picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать картинку: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<bool> _waitForFile(String path) async {
    final f = File(path);
    for (var i = 0; i < 20; i++) {
      try {
        if (await f.exists() && await f.length() > 0) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> _resetImage() async {
    final key = widget.avatarKey;
    if (key == null) return;
    await AvatarStorage.clear(key);
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.avatarKey;
    if (key == null) return _render(null);

    return ValueListenableBuilder<int>(
      valueListenable: AvatarStorage.revisionFor(key),
      builder: (context, _, _) => _render(AvatarStorage.cachedPath(key)),
    );
  }

  Widget _render(String? localPath) {
    final theme = Theme.of(context);
    final hasLocal = localPath != null && localPath.isNotEmpty;
    final hasNetwork =
        !hasLocal && widget.photoUrl != null && widget.photoUrl!.isNotEmpty;

    Widget imageWidget;
    if (hasLocal) {
      imageWidget = Image(
        image: FileImage(File(localPath)),
        // Ключ по пути: при смене картинки Flutter пересоздаст элемент
        // и не подсунет старый кадр из кэша.
        key: ValueKey(localPath),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _initialsBox(theme),
      );
    } else if (hasNetwork) {
      imageWidget = Image.network(
        widget.photoUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _initialsBox(theme),
      );
    } else {
      imageWidget = _initialsBox(theme);
    }

    final avatar = ClipOval(
      child: SizedBox(
        width: widget.radius * 2,
        height: widget.radius * 2,
        child: imageWidget,
      ),
    );

    if (widget.avatarKey == null) return avatar;

    return GestureDetector(
      onTap: _pickImage,
      onLongPress: _resetImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          avatar,
          if (_loading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else if (widget.radius >= 20)
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(
                Icons.edit,
                size: widget.radius * 0.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialsBox(ThemeData theme) => Container(
    alignment: Alignment.center,
    color: theme.colorScheme.primaryContainer,
    child: Text(
      initials(widget.fullName),
      style: TextStyle(
        fontSize: widget.radius * 0.6,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    ),
  );
}
