import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/auth/epos_session.dart';
import '../core/network/epos_http_client.dart';
import '../models/homework_attachment.dart';

class AttachmentOpenResult {
  final bool ok;
  final String? error;
  const AttachmentOpenResult._(this.ok, this.error);
  const AttachmentOpenResult.success() : this._(true, null);
  const AttachmentOpenResult.failure(String error) : this._(false, error);
}

/// Скачивает файлы ДЗ из ЭПОСа и открывает их системным приложением
/// (PDF-вьюер, галерея, офисный пакет — что найдётся).
///
/// Файлы лежат на том же домене, что и API, и требуют ту же
/// аутентификацию — cookies. Качаем через createEposHttpClient() и
/// подкладываем те же заголовки, что и в ApiClient.
///
/// Сессия передаётся снаружи через setSession(): кнопка живёт глубоко
/// в дереве, тащить токены через конструкторы всех виджетов — лишнее.
/// HomeScreen выставляет её в initState и после каждой re-auth.
class AttachmentService {
  AttachmentService._();
  static final instance = AttachmentService._();

  static const _userAgent = 'okhttp/4.12.0';

  EposSession? _session;
  void setSession(EposSession? session) => _session = session;

  static const _subdir = 'attachments';

  Future<AttachmentOpenResult> open(
    HomeworkAttachment att, {
    void Function(double progress)? onProgress,
  }) async {
    if (att.url.isEmpty) {
      return const AttachmentOpenResult.failure('Пустая ссылка на файл');
    }
    final session = _session;
    if (session == null) {
      return const AttachmentOpenResult.failure('Нет активной сессии');
    }

    try {
      final file = await _target(att.name);

      // Если файл уже скачан с прошлого раза — не тянем повторно.
      final cached = await file.exists() && await file.length() > 0;
      if (!cached) {
        final ok = await _download(att.url, file, session, onProgress);
        if (!ok) {
          return const AttachmentOpenResult.failure('Не удалось скачать файл');
        }
      } else {
        onProgress?.call(1);
      }

      final res = await OpenFilex.open(file.path);
      if (res.type != ResultType.done) {
        return AttachmentOpenResult.failure(
          res.message.isEmpty
              ? 'Нет приложения, которое откроет этот файл'
              : res.message,
        );
      }
      return const AttachmentOpenResult.success();
    } catch (e) {
      return AttachmentOpenResult.failure('Ошибка: $e');
    }
  }

  /// Куда сохранять. Имя из внешнего источника — режем всё, что может
  /// быть путём (слэши, двоеточия, wildcard и т.п.), оставляем basename.
  Future<File> _target(String name) async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return File(p.join(dir.path, safe.isEmpty ? 'file' : safe));
  }

  Future<bool> _download(
    String url,
    File dest,
    EposSession session,
    void Function(double)? onProgress,
  ) async {
    final client = await createEposHttpClient();
    IOSink? sink;
    var ok = false;
    try {
      final headers = <String, String>{
        'Accept': '*/*',
        'User-Agent': _userAgent,
      };
      if (session.cookieHeader.isNotEmpty) {
        headers['Cookie'] = session.cookieHeader;
      } else {
        headers['Auth-Token'] = session.authToken;
        headers['Profile-Id'] = session.profileId;
      }

      final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);

      final resp = await client.send(req);
      if (resp.statusCode != 200) return false;

      final total = resp.contentLength ?? 0;
      var received = 0;
      sink = dest.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      ok = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      // Неполную закачку не оставляем: иначе следующий тап решит,
      // что файл уже есть, и откроет битый.
      if (!ok) {
        try {
          if (await dest.exists()) await dest.delete();
        } catch (_) {}
      }
      client.close();
    }
  }
}
