import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/auth/auth_coordinator.dart';
import '../core/network/api_client.dart';
import '../core/network/epos_http_client.dart';
import '../core/util/date_time.dart';
import '../models/homework_attachment.dart';
import 'auth_service.dart';
import 'session_expired_exception.dart';
import '../core/auth/session_notifier.dart';
import 'epos_response_guard.dart';

/// Прикрепление и удаление файлов ученика к ДЗ.
///
/// Протокол (снят с веб-клиента ЭПОСа):
///   1. POST   /core/api/attachments?pid=…        multipart: file + file_name
///      → {id, file_file_name, file_content_type, file_file_size, path}
///   2. PUT    /core/api/student_homeworks/{id}?pid=…   ЦЕЛИКОМ сущность,
///      где attachments[] += объект из шага 1, attachment_ids[] += его id.
///   Удаление: PUT с вычеркнутым файлом, затем
///   3. DELETE /core/api/attachments/{attId}?pid=…
///
/// Важно: PUT принимает не патч, а всю запись — поэтому её сначала
/// вычитываем с сервера. Мусорные поля веб-клиента (restangularized,
/// reqParams, headers) серверу не нужны и не отправляются.
class HomeworkAttachmentsService {
  HomeworkAttachmentsService._();
  static final instance = HomeworkAttachmentsService._();

  static const _base = 'https://edu-epos.permkrai.ru';
  final _api = ApiClient();

  EposTokens? get _tokens => AuthCoordinator.instance.tokens;

  /// Текущее состояние: какие файлы ученика висят на этом ДЗ.
  Future<List<HomeworkAttachment>> load(int studentHomeworkId) async {
    final entity = await _fetchEntity(studentHomeworkId);
    return _readAttachments(entity);
  }

  Future<List<HomeworkAttachment>> attach(
      int studentHomeworkId, {
        required String filePath,
        required String fileName,
      }) async {
    final uploaded = await _upload(filePath, fileName);
    final entity = await _fetchEntity(studentHomeworkId);

    final attachments = _rawAttachments(entity)..add(uploaded);
    final ids = attachments
        .map((a) => a['id'])
        .whereType<int>()
        .toList();

    final updated = await _putEntity(studentHomeworkId, entity, attachments, ids);
    return _readAttachments(updated);
  }

  Future<List<HomeworkAttachment>> detach(
      int studentHomeworkId,
      int attachmentId,
      ) async {
    final entity = await _fetchEntity(studentHomeworkId);

    final attachments = _rawAttachments(entity)
      ..removeWhere((a) => a['id'] == attachmentId);
    final ids = attachments.map((a) => a['id']).whereType<int>().toList();

    final updated =
    await _putEntity(studentHomeworkId, entity, attachments, ids);

    // Сам файл убираем вторым шагом: сначала он должен перестать быть
    // привязанным, иначе сервер может отказать в удалении.
    await _deleteAttachment(attachmentId);
    return _readAttachments(updated);
  }

  // ── HTTP ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _upload(String path, String name) async {
    return _withAuthRetry((tokens) async {
      final client = await createEposHttpClient();
      try {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('$_base/core/api/attachments?pid=${tokens.profileId}'),
        )
          ..headers.addAll(_headers(tokens))
          ..fields['file_name'] = name
          ..files.add(await http.MultipartFile.fromPath(
            'file',
            path,
            filename: name,
          ));

        final streamed = await client.send(req).timeout(
          const Duration(seconds: 120),
        );
        final body = await streamed.stream.bytesToString();
        final resp = http.Response(body, streamed.statusCode);
        ensureSessionValid(resp);
        if (resp.statusCode >= 400) {
          throw Exception('Загрузка файла: ${resp.statusCode} $body');
        }
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Загрузка файла: неожиданный ответ');
        }
        return decoded;
      } finally {
        client.close();
      }
    });
  }

  Future<Map<String, dynamic>> _putEntity(
      int id,
      Map<String, dynamic> entity,
      List<Map<String, dynamic>> attachments,
      List<int> attachmentIds,
      ) async {
    final payload = Map<String, dynamic>.from(entity)
      ..['attachments'] = attachments
      ..['attachment_ids'] = attachmentIds;

    return _withAuthRetry((tokens) async {
      final client = await createEposHttpClient();
      try {
        final resp = await client
            .put(
          Uri.parse(
            '$_base/core/api/student_homeworks/$id?pid=${tokens.profileId}',
          ),
          headers: {
            ..._headers(tokens),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
            .timeout(const Duration(seconds: 30));
        ensureSessionValid(resp);
        if (resp.statusCode >= 400) {
          throw Exception('Сохранение ДЗ: ${resp.statusCode}');
        }
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        return decoded is Map<String, dynamic> ? decoded : payload;
      } finally {
        client.close();
      }
    });
  }

  Future<void> _deleteAttachment(int attachmentId) async {
    await _withAuthRetry((tokens) async {
      final client = await createEposHttpClient();
      try {
        final resp = await client
            .delete(
          Uri.parse(
            '$_base/core/api/attachments/$attachmentId'
                '?pid=${tokens.profileId}',
          ),
          headers: _headers(tokens),
        )
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          throw const SessionExpiredException();
        }
        return true;
      } finally {
        client.close();
      }
    });
  }

  /// Сущность целиком. Основной путь — GET по id; если сервер такой
  /// маршрут не отдаёт, ищем запись в списке за учебный год.
  Future<Map<String, dynamic>> _fetchEntity(int id) async {
    final tokens = _requireTokens();
    try {
      final raw = await _api.getRaw(
        Uri.parse(
          '$_base/core/api/student_homeworks/$id?pid=${tokens.profileId}',
        ),
        tokens,
        attempts: 2,
      );
      if (raw is Map<String, dynamic> && raw['id'] is int) return raw;
    } catch (_) {
      // падаем в фолбэк ниже
    }

    final now = DateTime.now();
    final year = now.month >= 9 ? now.year : now.year - 1;
    final list = await _api.getList(
      Uri.parse(
        '$_base/core/api/student_homeworks'
            '?begin_date=${dotDate(DateTime(year, 9, 1))}'
            '&end_date=${dotDate(DateTime(year + 1, 8, 31))}'
            '&student_profile_id=${tokens.profileId}'
            '&page=1&per_page=1000'
            '&pid=${tokens.profileId}',
      ),
      tokens,
      attempts: 2,
    );
    for (final raw in list.whereType<Map<String, dynamic>>()) {
      if (raw['id'] == id) return raw;
    }
    throw Exception('Запись ДЗ $id не найдена на сервере');
  }

  // ── Вспомогательное ────────────────────────────────────────────────────

  EposTokens _requireTokens() {
    final t = _tokens;
    if (t == null) throw Exception('Нет активной сессии');
    return t;
  }

  Map<String, String> _headers(EposTokens tokens) => {
    'Auth-Token': tokens.authToken,
    'Profile-Id': tokens.profileId,
    'Accept': 'application/json',
  };

  /// Эти запросы идут мимо ApiClient (multipart/PUT/DELETE), поэтому
  /// автопродление сессии дублируем здесь вручную.
  Future<T> _withAuthRetry<T>(
      Future<T> Function(EposTokens tokens) action,
      ) async {
    try {
      return await action(_requireTokens());
    } on SessionExpiredException {
      final outcome = await AuthCoordinator.instance.renew();
      switch (outcome) {
        case RenewOutcome.success:
          return action(_requireTokens());
        case RenewOutcome.authDead:
          SessionNotifier.instance.markExpired();
          rethrow;
        case RenewOutcome.networkError:
          throw Exception('Нет соединения — попробуй ещё раз позже');
      }
    }
  }

  static List<Map<String, dynamic>> _rawAttachments(
      Map<String, dynamic> entity,
      ) {
    final raw = entity['attachments'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((a) => <String, dynamic>{
      'id': a['id'],
      'file_file_name': a['file_file_name'],
      'file_content_type': a['file_content_type'],
      'file_file_size': a['file_file_size'],
      'path': a['path'],
    })
        .toList();
  }

  static List<HomeworkAttachment> _readAttachments(
      Map<String, dynamic> entity,
      ) {
    final raw = entity['attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HomeworkAttachment.fromJson)
        .where((a) => a.url.isNotEmpty)
        .toList();
  }
}

/// Утилита выбора файла системным пикером Android (SAF).
class PickedFile {
  final String path;
  final String name;
  const PickedFile(this.path, this.name);

  static Future<PickedFile?> pick() async {
    // Импорт внутри метода не нужен — см. file_picker в pubspec.
    throw UnimplementedError();
  }
}

/// Убираем временный файл, скачанный пикером во временный кэш.
Future<void> disposeTemp(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}