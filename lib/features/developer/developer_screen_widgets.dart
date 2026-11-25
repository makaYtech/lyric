part of 'developer_screen.dart';

class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Какие-либо действия на этом экране могут привести к поломке '
              'работоспособности приложения. Настоятельно не '
              'рекомендуется трогать без нужды.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool danger;

  const _Section({
    required this.title,
    required this.children,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: danger ? theme.colorScheme.error : null,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Card(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : null;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: enabled ? onTap : null,
    );
  }
}

class _KeyStatusTile extends StatelessWidget {
  final String? key_;

  const _KeyStatusTile({required this.key_});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = key_ != null && key_!.isNotEmpty;
    final display = has ? 'есть (${key_!.length} симв.)' : '—';

    return ListTile(
      leading: const Icon(Icons.vpn_key_outlined),
      title: const Text('Текущий device_key'),
      subtitle: Text(
        display,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SessionStatusTile extends StatelessWidget {
  final DebugSnapshot? snapshot;

  const _SessionStatusTile({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = snapshot?.epos;

    if (s == null) {
      return ListTile(
        leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
        title: const Text('Сессия отсутствует'),
        subtitle: const Text('Secure storage пуст'),
      );
    }

    final oauth = s.refreshToken != null
        ? 'есть${s.accessExpiresAt != null ? " (${_expiresLabel(s.accessExpiresAt!)})" : ""}'
        : 'нет';

    final cookies = s.cookies;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(theme, 'Текущее состояние'),
          const SizedBox(height: 6),
          _row(
            theme,
            'flow',
            s.deviceToken != null ? 'device-token' : 'legacy OAuth',
          ),
          _row(theme, 'device_token', _presence(s.deviceToken)),
          _row(theme, 'auth_token (UUID)', _presence(s.authToken)),
          _row(theme, 'profile_id', s.profileId),
          _row(theme, 'OAuth-пара', oauth),
          const SizedBox(height: 12),
          _label(theme, 'Cookies (${cookies.length})'),
          const SizedBox(height: 6),
          if (cookies.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final entry in cookies.entries)
              _row(theme, entry.key, _cookieValue(entry.value)),
        ],
      ),
    );
  }

  static Widget _label(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.3,
    ),
  );

  /// "true"/"false" показываем как есть — длина бессмысленна; остальное —
  /// «есть (N симв.)», а маркер POISONED_ подсвечиваем.
  static String _cookieValue(String v) {
    if (v.isEmpty) return '—';
    if (v == 'true' || v == 'false') return v;
    if (v.startsWith('POISONED_')) return 'ОТРАВЛЕНО';
    return 'есть (${v.length} симв.)';
  }

  static String _presence(String? v) {
    if (v == null || v.isEmpty) return '—';
    if (v.startsWith('POISONED_')) return 'ОТРАВЛЕНО';
    return 'есть (${v.length} симв.)';
  }

  static String _expiresLabel(DateTime exp) {
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return 'просрочен';
    if (diff.inMinutes < 1) return 'меньше минуты';
    if (diff.inHours < 1) return '${diff.inMinutes} мин';
    return '${diff.inHours} ч';
  }

  static Widget _row(ThemeData theme, String label, String value) {
    final isPoisoned = value == 'ОТРАВЛЕНО';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isPoisoned ? theme.colorScheme.error : null,
                fontWeight: isPoisoned ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
