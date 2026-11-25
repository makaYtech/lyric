import 'package:flutter/material.dart';

import '../../widgets/auth/device_auth_view.dart';

/// Перелогин по device-token flow: возвращает EposSession через pop.
class DeviceReauthScreen extends StatelessWidget {
  const DeviceReauthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DeviceAuthView(
      deadMessage: 'Не удалось получить сессию. Попробуйте ещё раз.',
      onSession: (ctx, session) => Navigator.of(ctx).pop(session),
    );
  }
}
