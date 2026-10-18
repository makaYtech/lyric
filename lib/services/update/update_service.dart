import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/layout/adaptive.dart';
import '../../core/settings/update_prefs.dart';

/// ────────────────────────────────────────────────────────────────────
/// Модель одного канала из update.json.
/// ────────────────────────────────────────────────────────────────────
class UpdateInfo {
  final String version;
  final String changelog;
  final int sizeBytes;
  final String sha256;
  final String apkName;

  /// Необязательно: прямая ссылка на страницу загрузки (desktop). Если пусто —
  /// берётся страница релиза v<version> в репозитории.
  final String pageUrl;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.sizeBytes,
    required this.sha256,
    required this.apkName,
    this.pageUrl = '',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) => UpdateInfo(
    version: (j['version'] as String? ?? '').trim(),
    changelog: (j['changelog'] as String? ?? '').trim(),
    sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
    sha256: (j['sha256'] as String? ?? '').trim().toLowerCase(),
    apkName: (j['apk_name'] as String? ?? '').trim(),
    pageUrl: (j['page_url'] as String? ?? '').trim(),
  );

  String get displaySize {
    if (sizeBytes <= 0) return '—';
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
}

/// ────────────────────────────────────────────────────────────────────
/// Результат проверки.
/// ────────────────────────────────────────────────────────────────────
enum UpdateCheckResult { upToDate, available, networkError, parseError }

class UpdateCheck {
  final UpdateCheckResult result;
  final UpdateInfo? info;
  final String currentVersion;
  final String? error;

  const UpdateCheck._({
    required this.result,
    required this.currentVersion,
    this.info,
    this.error,
  });

  const UpdateCheck.upToDate(String current)
    : this._(result: UpdateCheckResult.upToDate, currentVersion: current);

  const UpdateCheck.available(UpdateInfo info, String current)
    : this._(
        result: UpdateCheckResult.available,
        info: info,
        currentVersion: current,
      );

  const UpdateCheck.networkError(String e, String current)
    : this._(
        result: UpdateCheckResult.networkError,
        error: e,
        currentVersion: current,
      );

  const UpdateCheck.parseError(String e, String current)
    : this._(
        result: UpdateCheckResult.parseError,
        error: e,
        currentVersion: current,
      );
}

/// ────────────────────────────────────────────────────────────────────
/// Результат скачивания.
/// ────────────────────────────────────────────────────────────────────
class UpdateDownloadResult {
  final File? file;
  final String? error;

  const UpdateDownloadResult._({this.file, this.error});
  const UpdateDownloadResult.success(File f) : this._(file: f);
  const UpdateDownloadResult.failure(String e) : this._(error: e);
  const UpdateDownloadResult.cancelled() : this._(error: 'Скачивание отменено');
}

class UpdateInstallResult {
  final bool ok;
  final String? error;
  const UpdateInstallResult._(this.ok, this.error);
  const UpdateInstallResult.success() : this._(true, null);
  const UpdateInstallResult.failure(String e) : this._(false, e);
}

/// ────────────────────────────────────────────────────────────────────
/// Сервис обновлений через GitHub Releases.
///
///   • update.json лежит в main-ветке репозитория, читается через
///     raw.githubusercontent.com — там нет rate limit'а на анонимные
///     запросы (в отличие от api.github.com).
///   • APK лежит в GitHub Releases, по пути
///     releases/download/v<version>/<apk_name>.
///   • Скачивание с 5 попытками, SHA-256 проверяется после каждой.
///   • Установка — через OpenFilex с MIME-типом APK; открывается
///     системный пакетный установщик.
/// ────────────────────────────────────────────────────────────────────
class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  // ⚠️ ЗАМЕНИ ЭТИ ДВЕ СТРОКИ ПОСЛЕ СОЗДАНИЯ РЕПОЗИТОРИЯ.
  static const _owner = 'makaYtech';
  static const _repo = 'lyric_apk';

  static const _updateJsonUrl =
      'https://raw.githubusercontent.com/$_owner/$_repo/main/docs/update.json';
  static const _releaseBase =
      'https://github.com/$_owner/$_repo/releases/download';

  static const _maxAttempts = 5;

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
    ),
  );

  PackageInfo? _cachedPkg;

  Future<PackageInfo> _pkg() async =>
      _cachedPkg ??= await PackageInfo.fromPlatform();

  Future<String> currentVersion() async => (await _pkg()).version;

  /// Проверка наличия новой версии в указанном канале.
  Future<UpdateCheck> check(UpdateChannel channel) async {
    final current = await currentVersion();

    try {
      final resp = await _dio.get<String>(
        _updateJsonUrl,
        options: Options(
          responseType: ResponseType.plain,
          // GitHub raw отдаёт без кэша; на всякий случай.
          headers: {'Cache-Control': 'no-cache'},
        ),
      );
      final body = resp.data;
      if (body == null || body.isEmpty) {
        return UpdateCheck.parseError('Пустой ответ update.json', current);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheck.parseError('update.json — не объект', current);
      }

      final entry = decoded[channel.name];
      if (entry is! Map<String, dynamic>) {
        // Канал отсутствует в файле — считаем, что обновлений нет.
        return UpdateCheck.upToDate(current);
      }

      final info = UpdateInfo.fromJson(entry);
      // На desktop APK не нужен: приложение только сообщает о новой версии
      // и открывает страницу загрузки, поэтому sha256/apk_name не требуем.
      if (info.version.isEmpty ||
          (!AdaptiveLayout.isDesktopOS &&
              (info.sha256.isEmpty || info.apkName.isEmpty))) {
        return UpdateCheck.parseError(
          'update.json: не все поля заполнены',
          current,
        );
      }

      if (!_isNewer(info.version, current)) {
        return UpdateCheck.upToDate(current);
      }
      return UpdateCheck.available(info, current);
    } on DioException catch (e) {
      return UpdateCheck.networkError(e.message ?? e.toString(), current);
    } catch (e) {
      return UpdateCheck.parseError('$e', current);
    }
  }

  /// Страница загрузки для desktop (Windows/Linux): явная `page_url` из
  /// update.json или страница релиза v<version>.
  String releasePageUrl(UpdateInfo info) => info.pageUrl.isNotEmpty
      ? info.pageUrl
      : 'https://github.com/$_owner/$_repo/releases/tag/v${info.version}';

  /// Скачивание и верификация. Пробует до 5 раз.
  /// [cancelToken] — чтобы прервать, если пользователь закрыл шторку.
  Future<UpdateDownloadResult> downloadAndVerify(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getTemporaryDirectory();
    final updatesDir = Directory('${dir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    final dest = File('${updatesDir.path}/${info.apkName}');

    Object? lastError;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      // Пользователь мог отменить — выходим сразу.
      if (cancelToken?.isCancelled ?? false) {
        return const UpdateDownloadResult.cancelled();
      }

      try {
        if (await dest.exists()) await dest.delete();

        await _dio.download(
          '$_releaseBase/v${info.version}/${info.apkName}',
          dest.path,
          cancelToken: cancelToken,
          options: Options(headers: {'Accept': 'application/octet-stream'}),
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );

        final actual = await _sha256OfFile(dest);
        if (actual.toLowerCase() != info.sha256.toLowerCase()) {
          lastError =
              'SHA-256 не совпал '
              '(получено ${actual.substring(0, 12)}…, '
              'ожидалось ${info.sha256.substring(0, 12)}…)';
          await dest.delete();
        } else {
          return UpdateDownloadResult.success(dest);
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          return const UpdateDownloadResult.cancelled();
        }
        lastError = e.message ?? e.toString();
        try {
          if (await dest.exists()) await dest.delete();
        } catch (_) {}
      } catch (e) {
        lastError = e;
        try {
          if (await dest.exists()) await dest.delete();
        } catch (_) {}
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return UpdateDownloadResult.failure(
      'Не удалось скачать после $_maxAttempts попыток: $lastError',
    );
  }

  /// Открывает системный установщик. Если вернётся ok — интент ушёл,
  /// Android покажет диалог «Установить приложение?». Если пользователь
  /// подтвердит — система сама убьёт наш процесс и заменит APK.
  Future<UpdateInstallResult> install(File apk) async {
    try {
      final res = await OpenFilex.open(
        apk.path,
        type: 'application/vnd.android.package-archive',
      );
      if (res.type != ResultType.done) {
        return UpdateInstallResult.failure(
          res.message.isEmpty ? 'Система не открыла установщик' : res.message,
        );
      }
      return const UpdateInstallResult.success();
    } catch (e) {
      return UpdateInstallResult.failure('$e');
    }
  }

  // ── Вспомогательное ────────────────────────────────────────────────

  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Сравнение «semver-подобных» строк с поддержкой -beta/-alpha.
  ///   "1.0.1"       > "1.0.0"
  ///   "1.0.1-beta"  > "1.0.0"
  ///   "1.0.1-beta"  < "1.0.1"       (пререлиз старше релиза)
  ///   "1.0.2"       > "1.0.1-beta"
  static bool _isNewer(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);

    if (r.major != l.major) return r.major > l.major;
    if (r.minor != l.minor) return r.minor > l.minor;
    if (r.patch != l.patch) return r.patch > l.patch;

    // Числовая часть одинаковая: релиз > пререлиз.
    final rStable = r.pre.isEmpty;
    final lStable = l.pre.isEmpty;
    if (rStable != lStable) return rStable;

    // Оба пререлиза — сравниваем строкой (beta.2 > beta.1).
    if (!rStable) return r.pre.compareTo(l.pre) > 0;
    return false;
  }

  static _Version _parseVersion(String v) {
    final clean = v.trim().replaceFirst(RegExp(r'^v'), '');
    final dash = clean.indexOf('-');
    final numeric = dash < 0 ? clean : clean.substring(0, dash);
    final pre = dash < 0 ? '' : clean.substring(dash + 1);

    final parts = numeric.split('.');
    int at(int i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0;

    return _Version(major: at(0), minor: at(1), patch: at(2), pre: pre);
  }
}

class _Version {
  final int major, minor, patch;
  final String pre;
  const _Version({
    required this.major,
    required this.minor,
    required this.patch,
    required this.pre,
  });
}
