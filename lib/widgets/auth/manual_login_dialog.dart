import 'package:flutter/material.dart';

/// Пара ручного ввода для debug-входа без Госуслуг: токен + profile id.
class ManualCredentials {
  final String token;
  final String profileId;

  const ManualCredentials({required this.token, required this.profileId});
}

/// Ctrl+Shift+D на экране входа открывает это окно.
Future<ManualCredentials?> showManualLoginDialog(BuildContext context) {
  return showDialog<ManualCredentials>(
    context: context,
    builder: (_) => const _ManualLoginDialog(),
  );
}

class _ManualLoginDialog extends StatefulWidget {
  const _ManualLoginDialog();

  @override
  State<_ManualLoginDialog> createState() => _ManualLoginDialogState();
}

class _ManualLoginDialogState extends State<_ManualLoginDialog> {
  final _token = TextEditingController();
  final _profileId = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _token.dispose();
    _profileId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Вход по токену'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'device-токен (UUID из diaryperm://redirect?token=...)',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _token,
              autofocus: true,
              obscureText: _obscure,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'profile_id (из cookie профиля)',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _profileId,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '17916434',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Войти')),
      ],
    );
  }

  void _submit() {
    final token = _token.text.trim();
    final profileId = _profileId.text.trim();
    if (token.isEmpty || profileId.isEmpty) return;
    Navigator.of(context)
        .pop(ManualCredentials(token: token, profileId: profileId));
  }
}
