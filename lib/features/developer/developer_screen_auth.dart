part of 'developer_screen.dart';

extension _DeveloperAuthActions on _DeveloperScreenState {
  Future<void> _toggleAuthFlow(bool useDevice) async {
    final current = AuthConfig.useDeviceTokenFlow.value;
    if (current == useDevice) return;

    final ok = await _confirm(
      title: 'Сменить flow авторизации?',
      body: useDevice
          ? 'Включить device-token flow (новый). Текущая сессия будет '
                'сброшена — потребуется войти заново. Кэш и device_key '
                'останутся на месте.'
          : 'Включить legacy OAuth flow (PKCE + refresh_token + Phase C). '
                'Текущая сессия будет сброшена — потребуется войти заново. '
                'Используй, если новый flow не работает на стороне сервера.',
      confirmLabel: 'Сменить и выйти',
    );
    if (!ok) return;

    await AuthConfig.setUseDeviceTokenFlow(useDevice);
    await _tools.clearWholeEposSession();
    if (!mounted) return;
    _goToLogin();
  }

  Future<void> _pickPoisonTarget() async {
    final snap = await _tools.snapshot();
    if (!mounted) return;

    final hasDeviceToken = (snap.epos?.deviceToken ?? '').isNotEmpty;
    final cookies = snap.cookies;

    if (!hasDeviceToken && cookies.isEmpty) {
      _snack('Нечего отравлять — сессии нет');
      return;
    }

    final picked = await showDialog<_PoisonTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Что отравить?'),
        children: [
          if (hasDeviceToken)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(
                const _PoisonTarget(
                  name: 'device_token (UUID)',
                  isDeviceToken: true,
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('device_token (UUID)'),
              ),
            ),
          if (hasDeviceToken && cookies.isNotEmpty) const Divider(height: 1),
          for (final name in cookies.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(_PoisonTarget(name: name)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(name),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    if (picked.isDeviceToken) {
      await _run(
        _tools.poisonDeviceToken,
        successMessage: 'device_token отравлен',
      );
    } else {
      await _run(
        () => _tools.poisonCookie(picked.name),
        successMessage: 'Cookie "${picked.name}" отравлена',
      );
    }
  }

  Future<void> _pickResetTarget() async {
    final picked = await showDialog<_ResetTarget>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Что сбросить?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.deviceToken),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('device_token (UUID)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.oauthPair),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('OAuth-пара (access + refresh)'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ResetTarget.longToken),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('long_token'),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;

    switch (picked) {
      case _ResetTarget.deviceToken:
        await _run(
          _tools.clearDeviceToken,
          successMessage: 'device_token сброшен',
        );
      case _ResetTarget.oauthPair:
        await _run(
          _tools.clearOauthPair,
          successMessage: 'OAuth-пара сброшена',
        );
      case _ResetTarget.longToken:
        await _run(_tools.clearLongToken, successMessage: 'long_token сброшен');
    }
  }

  Future<void> _probeEndpoint() async {
    final controller = TextEditingController(
      text: '/core/api/profiles?ids=17938056',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Прямой запрос'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '/core/api/...',
            labelText: 'Path',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty || !mounted) return;

    final result = await _tools.probe(path);
    if (!mounted) return;
    _snack('$path → $result');
    _reload();
  }

  Future<void> _clearWholeEposSession() async {
    final ok = await _confirm(
      title: 'Сбросить всю сессию ЭПОС?',
      body:
          'Полное удаление сессии. Приложение попадёт на LoginScreen '
          'при следующем перезапуске. Сейчас не редиректим — можно '
          'посмотреть, как отреагирует HomeScreen.',
    );
    if (!ok) return;
    await _run(
      _tools.clearWholeEposSession,
      successMessage: 'Сессия ЭПОС сброшена',
    );
  }

  Future<void> _resetDeviceKey() async {
    final ok = await _confirm(
      title: 'Сбросить device_key?',
      body:
          'Следующий интерактивный вход сгенерирует новый ключ. '
          'Старый на сервере останется — сам по себе он бесполезен.',
    );
    if (!ok) return;
    await _run(_tools.resetDeviceKey, successMessage: 'device_key сброшен');
  }
}
