import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

/// Mica — полупрозрачная подложка окна Windows 11 (та же, что у «Параметров»
/// и проводника). Рисует её сама система (DWM), Flutter лишь делает свой
/// фон прозрачным. Работает на Windows 11 22H2+ (сборка 22621); на Windows 10
/// и Linux ничего не включается, и тема красит окно обычным сплошным цветом.
abstract final class Mica {
  /// true — Mica реально включена; тема читает это, чтобы сделать
  /// фон Scaffold прозрачным.
  static bool enabled = false;

  static bool get supported {
    if (!Platform.isWindows) return false;
    final m = RegExp(r'Build (\d+)')
        .firstMatch(Platform.operatingSystemVersion);
    final build = int.tryParse(m?.group(1) ?? '') ?? 0;
    return build >= 22621;
  }

  /// Вызывать в main() после ensureInitialized(), до DesktopWindow.init().
  static Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      await Window.initialize();
      enabled = supported;
    } catch (_) {
      enabled = false;
    }
  }

  static Future<void> apply(Brightness brightness) async {
    if (!enabled) return;
    try {
      await Window.setEffect(
        effect: WindowEffect.mica,
        dark: brightness == Brightness.dark,
      );
    } catch (_) {
      // Подложка — украшение, из-за неё приложение падать не должно.
    }
  }
}

/// Следит за светлой/тёмной темой и переключает Mica вслед за ней.
/// Ставится в MaterialApp.builder.
class MicaScope extends StatefulWidget {
  final Widget child;
  const MicaScope({super.key, required this.child});

  @override
  State<MicaScope> createState() => _MicaScopeState();
}

class _MicaScopeState extends State<MicaScope> {
  Brightness? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (b != _last) {
      _last = b;
      Mica.apply(b);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
