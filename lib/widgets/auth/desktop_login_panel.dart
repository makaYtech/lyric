import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_config.dart';

// Синхронно с device_token_auth.dart.
const _base = 'https://edu-epos.permkrai.ru';
const _deepLinkScheme = 'diaryperm://';

/// Закрывать ли окно входа программно после получения токена.
///
/// Нужен desktop_webview_window >= 0.3.1: в 0.2.x закрытие окна на Linux
/// роняло всё приложение (use-after-free, исправлено в 0.3.1).
/// Если на старой версии снова падает — поставь false.
const _closeWindowAfterLogin = true;

void _log(String m) => debugPrint('[DesktopLogin] $m');

String _safeUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return '<unparsable>';
  return u
      .replace(query: u.hasQuery ? '<query>' : null, fragment: '')
      .toString();
}

/// Вход через ЭСИА на desktop (Linux/Windows).
///
/// webview_flutter на desktop не реализован, поэтому логин открывается
/// в ОТДЕЛЬНОМ окне (desktop_webview_window: webkit2gtk / WebView2).
/// Как только окно уходит на diaryperm://redirect?token=<UUID>, окно
/// закрывается и токен уходит в [onTokenFound] — дальше всё как на Android
/// (DeviceTokenAuthService.exchange).
///
/// Сам виджет — просто экран с кнопкой «Открыть окно входа»; окно при
/// этом открывается автоматически при первом показе.
class DesktopLoginPanel extends StatefulWidget {
  final void Function(String deviceToken) onTokenFound;
  final void Function(String status) onStatus;

  /// Подпись состояния от родителя («Обмен токена на сессию...» и т.п.).
  final String status;

  /// true — идёт обмен токена на сессию; кнопку и окно не трогаем.
  final bool busy;

  const DesktopLoginPanel({
    super.key,
    required this.onTokenFound,
    required this.onStatus,
    required this.status,
    required this.busy,
  });

  @override
  State<DesktopLoginPanel> createState() => _DesktopLoginPanelState();
}

class _DesktopLoginPanelState extends State<DesktopLoginPanel> {
  Webview? _window;
  bool _available = true;
  bool _tokenHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openWindow());
  }

  @override
  void dispose() {
    _closeWindowLater();
    super.dispose();
  }

  bool _closing = false;

  void _closeWindowLater() {
    final window = _window;
    if (!_closeWindowAfterLogin) {
      _log('close skipped (_closeWindowAfterLogin = false)');
      return;
    }
    if (window == null || _closing) return;
    _closing = true;
    Future.delayed(const Duration(milliseconds: 300), () {
      try {
        _log('calling close()');
        window.close();
      } catch (_) {}
    });
  }

  Future<String> _userDataFolder() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'webview');
  }

  Future<void> _openWindow() async {
    if (_window != null || widget.busy) return;

    if (!await WebviewWindow.isWebviewAvailable()) {
      if (!mounted) return;
      setState(() => _available = false);
      return;
    }

    _log('create window...');
    _tokenHandled = false;
    _closing = false;
    try {
      final window = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: 1000,
          windowHeight: 760,
          title: 'Вход в ЭПОС',
          // 0 — без Flutter-заголовка. На Linux это же отключает второй
          // Flutter-движок для заголовка (он и был источником краша).
          titleBarHeight: 0,
          userDataFolderWindows: await _userDataFolder(),
        ),
      );
      _window = window;
      _log('window created');

      window
        ..setOnUrlRequestCallback((url) {
          _log('url: ${_safeUrl(url)}');
          // Обычные страницы (ЭСИА, edu-epos) — пропускаем.
          if (!url.startsWith(_deepLinkScheme)) return true;

          final token = Uri.tryParse(url)?.queryParameters['token'];
          if (token == null || token.isEmpty) {
            widget.onStatus('deep-link без token');
            return false;
          }
          if (_tokenHandled) return false;
          _tokenHandled = true;
          _log('token found, scheduling close');
          widget.onTokenFound(token);
          // Закрываем окно отложенно, не из самого колбэка навигации.
          _closeWindowLater();
          // diaryperm:// браузеру не нужен — навигацию блокируем.
          return false;
        })
        ..onClose.whenComplete(() {
          _log('onClose fired');
          _window = null;
          if (!mounted) return;
          if (!_tokenHandled) widget.onStatus('Окно входа закрыто');
          setState(() {});
        })
        ..launch('$_base${AuthConfig.deviceLoginStartPath}');

      _log('launched');
      widget.onStatus('Войдите в открывшемся окне');
      if (mounted) setState(() {});
    } catch (e) {
      _window = null;
      widget.onStatus('Не удалось открыть окно входа: $e');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOpen = _window != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _available ? Icons.open_in_new : Icons.error_outline,
                size: 40,
                color: _available ? cs.primary : cs.error,
              ),
              const SizedBox(height: 16),
              Text(
                _available
                    ? 'Вход через Госуслуги откроется в отдельном окне'
                    : 'Окно входа недоступно',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _available
                    ? widget.status
                    : Platform.isLinux
                    ? 'Нужна библиотека webkit2gtk-4.1 '
                          '(Gentoo: net-libs/webkit-gtk:4.1).'
                    : 'Нужен Microsoft Edge WebView2 Runtime.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (widget.busy)
                const CircularProgressIndicator()
              else if (_available)
                FilledButton.icon(
                  onPressed: isOpen ? null : _openWindow,
                  icon: const Icon(Icons.login),
                  label: Text(isOpen ? 'Окно открыто' : 'Открыть окно входа'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
