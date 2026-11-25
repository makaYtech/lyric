import 'dart:convert';

/// Вложение к ДЗ из homework_entry.attachments[].
/// Поля 1:1 с сервером: id, file_file_name, file_content_type,
/// file_file_size, path. Полный URL собирается из относительного path.
class HomeworkAttachment {
  final int id;
  final String name;
  final String url;
  final String contentType;
  final int sizeBytes;

  const HomeworkAttachment({
    required this.id,
    required this.name,
    required this.url,
    this.contentType = '',
    this.sizeBytes = 0,
  });

  static const _base = 'https://edu-epos.permkrai.ru';

  String get displaySize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }

  /// Понимает и сырой ответ API (path), и наш кэш (url); url в приоритете.
  factory HomeworkAttachment.fromJson(Map<String, dynamic> j) {
    final rawUrl = j['url'] as String?;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      return HomeworkAttachment(
        id: j['id'] as int? ?? 0,
        name: j['name'] as String? ?? '—',
        url: rawUrl,
        contentType: j['content_type'] as String? ?? '',
        sizeBytes: (j['size'] as num?)?.toInt() ?? 0,
      );
    }

    final rawPath = j['path'] as String? ?? '';
    final url = rawPath.isEmpty
        ? ''
        : rawPath.startsWith('http')
        ? rawPath
        : '$_base$rawPath';

    return HomeworkAttachment(
      id: j['id'] as int? ?? 0,
      name: j['file_file_name'] as String? ?? '—',
      url: url,
      contentType: j['file_content_type'] as String? ?? '',
      sizeBytes: (j['file_file_size'] as num?)?.toInt() ?? 0,
    );
  }

  /// Разбирает массив вложений; записи без URL отбрасываются.
  static List<HomeworkAttachment> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HomeworkAttachment.fromJson)
        .where((a) => a.url.isNotEmpty)
        .toList();
  }

  /// Разбирает JSON-строку из кэша (SQLite-колонка attachments_json).
  /// Битый JSON и пустое значение деградируют до пустого списка.
  static List<HomeworkAttachment> listFromJsonString(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      return listFromJson(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'content_type': contentType,
    'size': sizeBytes,
  };
}
