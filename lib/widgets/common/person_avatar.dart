import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/settings/avatar_storage.dart';
import '../../core/util/names.dart';

/// Круглая аватарка. Если есть сохранённый путь к картинке на диске —
/// показывает её (читая файл каждый раз с устройства), иначе — инициалы.
///
/// Если задан [avatarKey] — по тапу можно выбрать/заменить картинку
/// через системный picker; долгий тап — сбросить обратно на инициалы.
/// Файл никуда не копируется: в настройках хранится только путь.
///
/// Подписан на per-key нотифаер из [AvatarStorage] — перерисовывается
/// ровно тогда, когда меняется ЕГО ключ, а не при любой смене аватарок
/// в дереве (как было с глобальным revision). Плюс быстрый синхронный
/// путь через in-memory кэш: если ключ уже читали, первый кадр рисует
/// картинку без мигания инициалами.
class PersonAvatar extends StatefulWidget {
  final String fullName;
  final double radius;

  /// Ключ, под которым хранится путь к картинке. Если null — картинка
  /// не хранится, аватар всегда с инициалами, тап ничего не делает.
  final String? avatarKey;

  /// Внешний путь (например, из сетевого источника). Если задан и
  /// локальной картинки нет — используется он.
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
  String? _localPath;
  bool _loading = false;
  ValueNotifier<int>? _revision;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant PersonAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarKey != widget.avatarKey) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _attach() {
    final key = widget.avatarKey;
    if (key == null) {
      _localPath = null;
      return;
    }
    // Синхронный быстрый путь: если ключ уже читали из prefs — сразу
    // показываем, без await. Это критично, когда на экране 20 учителей:
    // без этого каждый build мигал бы фоллбэком на инициалы.
    if (AvatarStorage.isLoaded(key)) {
      _localPath = AvatarStorage.cachedPath(key);
    } else {
      _loadFromPrefs(key);
    }
    _revision = AvatarStorage.revisionFor(key);
    _revision!.addListener(_onRevision);
  }

  void _detach() {
    _revision?.removeListener(_onRevision);
    _revision = null;
  }

  void _onRevision() {
    final key = widget.avatarKey;
    if (key == null || !mounted) return;
    setState(() => _localPath = AvatarStorage.cachedPath(key));
  }

  Future<void> _loadFromPrefs(String key) async {
    final path = await AvatarStorage.path(key);
    if (!mounted || widget.avatarKey != key) return;
    setState(() => _localPath = path);
  }

  Future<void> _pickImage() async {
    final key = widget.avatarKey;
    if (key == null || _loading) return;
    setState(() => _loading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      await AvatarStorage.savePath(key, picked.path);
      // revision listener сам перечитает путь и сделает setState —
      // здесь только снимаем индикатор загрузки.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать картинку: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetImage() async {
    final key = widget.avatarKey;
    if (key == null) return;
    await AvatarStorage.clear(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocal = _localPath != null;
    final hasNetwork = !hasLocal &&
        widget.photoUrl != null &&
        widget.photoUrl!.isNotEmpty;

    final avatar = ClipOval(
      child: SizedBox(
        width: widget.radius * 2,
        height: widget.radius * 2,
        child: hasLocal
            ? Image.file(
          File(_localPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsBox(theme),
          cacheWidth: (widget.radius *
              2 *
              MediaQuery.of(context).devicePixelRatio)
              .round(),
        )
            : hasNetwork
            ? Image.network(
          widget.photoUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsBox(theme),
        )
            : _initialsBox(theme),
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
                  color: Colors.black.withOpacity(0.3),
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
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
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