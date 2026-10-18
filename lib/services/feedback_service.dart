import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Тип обращения. Уходит в форму текстом из [label].
/// Хочешь ещё один тип — добавь значение сюда и плитку в настройках.
enum FeedbackType {
  bug('Ошибка'),
  request('Отзыв или предложение');

  final String label;
  const FeedbackType(this.label);
}

enum FeedbackResult { sent, tooFast, notConfigured, failed }

/// Отправка обратной связи в Google Форму напрямую из приложения
/// (POST на `formResponse`, без открытия браузера).
///
/// В Google Форме должно быть 6 вопросов типа «Текст» / «Абзац»
/// (порядок и названия любые). Их `entry.…` ID прописываются ниже.
/// Как достать ID — см. комментарий у [_entryType].
abstract final class FeedbackService {
  /// ID формы — кусок ссылки между `/forms/d/e/` и `/viewform`:
  /// https://docs.google.com/forms/d/e/<ВОТ_ЭТО>/viewform
  static const String formId =
      '1FAIpQLSeXC79TyPZ96HKzGzFk55oYVmcXCoH8RU7yQTMnQFyL0TptgA';

  // Как достать ID полей: в редакторе формы ⋮ → «Получить ссылку для
  // предварительного заполнения», впиши в каждое поле что-нибудь
  // узнаваемое (1, 2, 3…), «Получить ссылку» — в URL будет
  // …entry.1234567890=1&entry.2345678901=2… Это и есть ID.
  static const String _entryType = 'entry.628348948'; // тип обращения
  static const String _entryMessage = 'entry.1833600391'; // основной текст
  static const String _entryDetails = 'entry.1962126264'; // шаги (для ошибок)
  static const String _entryContact = 'entry.951639779'; // контакт
  static const String _entryApp = 'entry.573113767'; // версия приложения
  static const String _entrySystem = 'entry.867914425'; // ОС

  static const int minLength = 10;
  static const int maxLength = 2000;
  static const Duration _cooldown = Duration(seconds: 30);

  static bool get isConfigured =>
      !formId.contains('ВСТАВЬ') &&
      ![
        _entryType,
        _entryMessage,
        _entryDetails,
        _entryContact,
        _entryApp,
        _entrySystem,
      ].any((e) => e.contains('XXXX'));

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
      // Статус разбираем сами: Google на ошибки отвечает HTML-страницей.
      validateStatus: (_) => true,
    ),
  );

  static DateTime? _lastSent;

  static Future<FeedbackResult> send({
    required FeedbackType type,
    required String message,
    String details = '',
    String contact = '',
    bool attachDiagnostics = true,
  }) async {
    if (!isConfigured) return FeedbackResult.notConfigured;

    final last = _lastSent;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      return FeedbackResult.tooFast;
    }

    final data = <String, String>{
      _entryType: type.label,
      _entryMessage: _clip(message, maxLength),
      _entryDetails: _clip(details, maxLength),
      _entryContact: _clip(contact, 200),
      _entryApp: attachDiagnostics ? await _appInfo() : '',
      _entrySystem: attachDiagnostics ? _systemInfo() : '',
    };

    try {
      final r = await _dio.post<String>(
        'https://docs.google.com/forms/d/e/$formId/formResponse',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        _lastSent = DateTime.now();
        return FeedbackResult.sent;
      }
      return FeedbackResult.failed;
    } catch (_) {
      return FeedbackResult.failed;
    }
  }

  static String _clip(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  static Future<String> _appInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return '';
    }
  }

  static String _systemInfo() => _clip(
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    150,
  );
}
