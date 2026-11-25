import 'package:flutter/material.dart';

import '../../widgets/auth/pkce_auth_view.dart';

/// Перелогин по legacy PKCE flow: возвращает EposSession через pop.
class ReauthScreen extends StatelessWidget {
  const ReauthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PkceAuthView(
      failureUi: true,
      onSession: (ctx, session) => Navigator.of(ctx).pop(session),
    );
  }
}
