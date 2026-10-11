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
///
/// Аутентификация — cookies (см. ApiClient). Заголовки Auth-Token /
/// Profile-Id оставлены fallback'ом для legacy-сессий.
class HomeworkAttachmentsService {
  HomeworkAttachmentsService._();
  static final instance = HomeworkAttachmentsService._();

  static const _base = 'https://edu-epos.permkrai.ru';
  static const _userAgent = 'okhttp/4.12.0';
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
    final ids = attachments.map((a) => a['id']).whereType<int>().toList();

    final updated = await _putEntity(
      studentHomeworkId,
      entity,
      attachments,
      ids,
    );
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

    final updated = await _putEntity(
      studentHomeworkId,
      entity,
      attachments,
      ids,
    );

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
        final req =
            http.MultipartRequest(
                'POST',
                Uri.parse(
                  '$_base/core/api/attachments?pid=${tokens.profileId}',
                ),
              )
              ..headers.addAll(_headers(tokens))
              ..fields['file_name'] = name
              ..files.add(
                await http.MultipartFile.fromPath('file', path, filename: name),
              );

        final streamed = await client
            .send(req)
            .timeout(const Duration(seconds: 120));

        // Читаем ответ как БАЙТЫ и собираем Response.bytes — тогда
        // package:http НЕ пытается перекодировать тело в latin1.
        // Конструктор http.Response(String, ...) внутри делает
        // latin1.encode(body), и падает, если в теле есть кириллица.
        // А сервер эхом возвращает имя файла («ДЗ.txt») — вот на нём
        // всё и рвалось.
        final rawBytes = await streamed.stream.toBytes();
        final resp = http.Response.bytes(rawBytes, streamed.statusCode);

        ensureSessionValid(resp);
        if (resp.statusCode >= 400) {
          final errBody = utf8.decode(rawBytes, allowMalformed: true);
          throw Exception('Загрузка файла: ${resp.statusCode} $errBody');
        }
        final decoded = jsonDecode(utf8.decode(rawBytes));
        if (decoded is! Map<String, dynamic>) {
          throw Exception('Загрузка файла: неожиданный ответ');
        }
        if (decoded['id'] is! int) {
          final errBody = utf8.decode(rawBytes, allowMalformed: true);
          throw Exception(
            'Загрузка файла: сервер не вернул id вложения. '
            'Ответ: $errBody',
          );
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

    // Явно готовим тело в UTF-8 байтах и отправляем через HttpClient
    // напрямую. package:http при Content-Type без charset кодирует
    // String-тело через latin1 → падает на кириллице (например,
    // «ДЗ.txt» в имени приложенного файла). Передавая байты напрямую,
    // полностью обходим эту логику.
    final bodyBytes = utf8.encode(jsonEncode(payload));

    return _withAuthRetry((tokens) async {
      final client = await createEposRawHttpClient();
      try {
        final uri = Uri.parse(
          '$_base/core/api/student_homeworks/$id?pid=${tokens.profileId}',
        );
        final req = await client.putUrl(uri);
        req.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.headers.set('Accept', 'application/json');
        req.headers.set('User-Agent', _userAgent);
        if (tokens.cookieHeader.isNotEmpty) {
          req.headers.set('Cookie', tokens.cookieHeader);
        } else {
          req.headers.set('Auth-Token', tokens.authToken);
          req.headers.set('Profile-Id', tokens.profileId);
        }
        req.add(bodyBytes);

        final resp = await req.close().timeout(const Duration(seconds: 30));
        final rawBody = await utf8.decoder.bind(resp).join();

        if (resp.statusCode == 401 || resp.statusCode == 403) {
          throw const SessionExpiredException();
        }
        if (resp.statusCode >= 400) {
          final snippet = rawBody.length > 300
              ? '${rawBody.substring(0, 300)}…'
              : rawBody;
          throw Exception('Сохранение ДЗ: ${resp.statusCode} $snippet');
        }
        if (rawBody.isEmpty) return payload;
        final decoded = jsonDecode(rawBody);
        return decoded is Map<String, dynamic> ? decoded : payload;
      } finally {
        client.close(force: true);
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
  ///
  /// ВАЖНО: в списке обязателен academic_year_id — без него ЭПОС
  /// возвращает пустоту или 400. Именно на этом attach и падал.
  Future<Map<String, dynamic>> _fetchEntity(int id) async {
    final tokens = _requireTokens();

    // 1. Прямой GET по id.
    try {
      final raw = await _api.getRaw(
        Uri.parse(
          '$_base/core/api/student_homeworks/$id?pid=${tokens.profileId}',
        ),
        tokens,
        attempts: 2,
      );
      if (raw is Map<String, dynamic> &&
          _idMatches(raw['id'], id) &&
          raw.containsKey('attachments')) {
        return raw;
      }
    } catch (_) {
      // падаем в фолбэк ниже
    }

    // 2. Fallback: список за учебный год с academic_year_id.
    final academicYearId = await _resolveAcademicYearId(tokens);
    final now = DateTime.now();
    final year = now.month >= 9 ? now.year : now.year - 1;

    final params = <String>[
      'begin_date=${dotDate(DateTime(year, 9, 1))}',
      'end_date=${dotDate(DateTime(year + 1, 8, 31))}',
      if (academicYearId != null) 'academic_year_id=$academicYearId',
      'student_profile_id=${tokens.profileId}',
      'page=1',
      'per_page=1000',
      'pid=${tokens.profileId}',
    ];

    final list = await _api.getList(
      Uri.parse('$_base/core/api/student_homeworks?${params.join('&')}'),
      tokens,
      attempts: 2,
    );
    for (final raw in list.whereType<Map<String, dynamic>>()) {
      if (_idMatches(raw['id'], id)) return raw;
    }
    throw Exception('Запись ДЗ $id не найдена на сервере');
  }

  static bool _idMatches(Object? rawId, int id) {
    if (rawId is int) return rawId == id;
    if (rawId is num) return rawId.toInt() == id;
    if (rawId is String) return int.tryParse(rawId) == id;
    return false;
  }

  Future<int?> _resolveAcademicYearId(EposTokens tokens) async {
    try {
      final years = await _api.getList(
        Uri.parse('$_base/core/api/academic_years?pid=${tokens.profileId}'),
        tokens,
        attempts: 1,
      );
      for (final y in years.whereType<Map<String, dynamic>>()) {
        if (y['current_year'] == true && y['id'] is int) {
          return y['id'] as int;
        }
      }
      for (final y in years.reversed.whereType<Map<String, dynamic>>()) {
        if (y['id'] is int) return y['id'] as int;
      }
    } catch (_) {}
    return null;
  }

  // ── Вспомогательное ────────────────────────────────────────────────────

  EposTokens _requireTokens() {
    final t = _tokens;
    if (t == null) throw Exception('Нет активной сессии');
    return t;
  }

  /// Cookie-аутентификация; Auth-Token/Profile-Id — fallback для legacy.
  Map<String, String> _headers(EposTokens tokens) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': _userAgent,
    };
    if (tokens.cookieHeader.isNotEmpty) {
      headers['Cookie'] = tokens.cookieHeader;
    } else {
      headers['Auth-Token'] = tokens.authToken;
      headers['Profile-Id'] = tokens.profileId;
    }
    return headers;
  }

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
          // ЭПОС часто отдаёт 401 на первый запрос с новыми cookies —
          // waf_cookie приживается только со второго раза. Даём 3 попытки
          // с нарастающей паузой, прежде чем поверить, что сессия мертва.
          for (var i = 0; i < 3; i++) {
            try {
              return await action(_requireTokens());
            } on SessionExpiredException {
              if (i == 2) rethrow;
              await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
            }
          }
          rethrow; // недостижимо
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
        .map(
          (a) => <String, dynamic>{
            'id': a['id'],
            'file_file_name': a['file_file_name'],
            'file_content_type': a['file_content_type'],
            'file_file_size': a['file_file_size'],
            'path': a['path'],
          },
        )
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
