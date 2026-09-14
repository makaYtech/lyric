/// Вложение к ДЗ — реальный файл из ЭПОСа.
///
/// Приходит внутри homework_entry.attachments[] в ответе
/// /core/api/student_homeworks. Поля 1:1 соответствуют серверу:
///   id, file_file_name, file_content_type, file_file_size, path.
///
/// Полный URL собирается тут же: path — относительный
/// ("/attachments/files/..."), а хост один — edu-epos.
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

  /// Парсит и сырой ответ API (path), и наш кэш (url) — оба варианта
  /// встречаются: toJson пишет уже готовый url, API отдаёт относительный
  /// path. Поле url имеет приоритет.
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'content_type': contentType,
    'size': sizeBytes,
  };
}