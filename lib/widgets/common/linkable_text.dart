import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// TLD, которые распознаём в «голых» доменах без схемы.
/// Латиница — основные мировые и постсоветские. Кириллица — `.рф` и
/// `.ру` на случай, если кто-то набрал домен в кириллической раскладке.
const _latinTlds = <String>[
  'ru',
  'su',
  'com',
  'net',
  'org',
  'edu',
  'gov',
  'io',
  'me',
  'info',
  'biz',
  'online',
  'site',
  'app',
  'dev',
  'tech',
  'store',
  'by',
  'kz',
  'ua',
  'de',
  'fr',
  'uk',
  'us',
  'co',
];
const _cyrillicTlds = <String>['рф', 'ру'];

final _tldPattern = <String>[
  ..._latinTlds,
  ..._cyrillicTlds,
].map(RegExp.escape).join('|');

/// Три случая в одном регексе:
///   1. явная схема: https://… / http://…
///   2. www. без схемы
///   3. голый домен с TLD из списка (опционально с путём и query)
///
/// Одинарную кавычку сознательно не исключаем из набора: она физически
/// не встречается в URL (кодируется в %27), а её отсутствие в классе
/// символов сильно упрощает регулярку. Хвостовая ' всё равно отрежется
/// [_trimTrailing].
final _linkPattern = RegExp(
  r'https?://[^\s<>"]+'
          r'|\bwww\.[^\s<>"]+'
          r'|\b[a-zA-Zа-яёА-ЯЁ0-9][a-zA-Zа-яёА-ЯЁ0-9.-]*'
          r'\.(?:' +
      _tldPattern +
      r')'
          r'(?:/[^\s<>"]*)?',
  caseSensitive: false,
  unicode: true,
);

/// Пунктуация, которую отрезаем от хвоста совпадения — почти наверняка
/// не часть URL (точка в конце предложения, запятая, кавычка и т.п.).
const _trailingPunct = {
  '.',
  ',',
  ';',
  ':',
  '!',
  '?',
  '»',
  '«',
  '"',
  "'",
  '`',
  '…',
};

/// Текст с автоматически распознанными ссылками.
///
/// Сам по себе НЕ делает текст выделяемым — для этого оберни его (или
/// всю модалку) в [SelectionArea]. Внутри используется `Text.rich`, и
/// `SelectionArea` работает с ним из коробки, не конфликтуя с
/// recognizer'ами на ссылках.
class LinkableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  const LinkableText(this.text, {super.key, this.style, this.textAlign});

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<InlineSpan>? _spans;
  String? _spansForText;
  TextStyle? _spansForBase;
  TextStyle? _spansForLink;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _spansFor(TextStyle base, TextStyle link) {
    if (_spans != null &&
        _spansForText == widget.text &&
        _spansForBase == base &&
        _spansForLink == link) {
      return _spans!;
    }
    _disposeRecognizers();
    _spans = _buildSpans(base, link);
    _spansForText = widget.text;
    _spansForBase = base;
    _spansForLink = link;
    return _spans!;
  }

  List<InlineSpan> _buildSpans(TextStyle base, TextStyle link) {
    final text = widget.text;
    final out = <InlineSpan>[];
    var last = 0;

    for (final m in _linkPattern.allMatches(text)) {
      final raw = m.group(0)!;
      final trimmed = _trimTrailing(raw);
      if (trimmed.isEmpty) continue;

      if (m.start > last) {
        out.add(TextSpan(text: text.substring(last, m.start), style: base));
      }

      final recognizer = TapGestureRecognizer()
        ..onTap = () => _openLink(_normalize(trimmed));
      _recognizers.add(recognizer);
      out.add(TextSpan(text: trimmed, style: link, recognizer: recognizer));

      // Если хвост обрезали — он останется в исходном тексте и попадёт
      // в следующий «обычный» span, а не потеряется.
      last = m.start + trimmed.length;
    }

    if (last < text.length) {
      out.add(TextSpan(text: text.substring(last), style: base));
    }
    return out;
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _snack('Не удалось открыть ссылку');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Не удалось открыть ссылку');
    } catch (_) {
      _snack('Не удалось открыть ссылку');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Убираем хвостовую пунктуацию, которая почти наверняка не часть
  /// URL. Парные скобки/кавычки учитываем: если внутри уже есть
  /// открывающая, закрывающую не трогаем.
  static String _trimTrailing(String s) {
    var end = s.length;
    while (end > 0) {
      final c = s[end - 1];
      if (_trailingPunct.contains(c)) {
        end--;
        continue;
      }
      if (c == ')') {
        final sub = s.substring(0, end);
        if (')'.allMatches(sub).length > '('.allMatches(sub).length) {
          end--;
          continue;
        }
      }
      if (c == ']') {
        final sub = s.substring(0, end);
        if (']'.allMatches(sub).length > '['.allMatches(sub).length) {
          end--;
          continue;
        }
      }
      if (c == '}') {
        final sub = s.substring(0, end);
        if ('}'.allMatches(sub).length > '{'.allMatches(sub).length) {
          end--;
          continue;
        }
      }
      break;
    }
    return s.substring(0, end);
  }

  static String _normalize(String raw) =>
      raw.contains('://') ? raw : 'https://$raw';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final link = base.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary.withValues(alpha: 0.4),
    );

    return Text.rich(
      TextSpan(children: _spansFor(base, link)),
      textAlign: widget.textAlign,
    );
  }
}
