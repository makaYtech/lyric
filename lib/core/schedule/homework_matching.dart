import '../../domain/homework/homework.dart';
import '../../domain/homework/homework_attachment.dart';
import '../util/date_time.dart';

/// Матчинг ДЗ к урокам — общая логика для сетевого запроса в
/// ScheduleService и пересборки из кэша в ScheduleRepository.
class HomeworkMatching {
  HomeworkMatching._();

  /// «Есть ли в тексте что-то, кроме "не задано"».
  static bool isMeaningful(String? raw) {
    if (raw == null) return false;
    final text = raw.trim();
    if (text.isEmpty) return false;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized != 'не задано';
  }

  /// byId — homework.id → Homework; byDue — iso(dueDate) → список Homework.
  static ({Map<int, Homework> byId, Map<String, List<Homework>> byDue})
  buildMaps(List<Homework> homeworks) {
    final byId = <int, Homework>{};
    final byDue = <String, List<Homework>>{};
    for (final h in homeworks) {
      if (h.homeworkId > 0) byId[h.homeworkId] = h;
      final d = h.dueDate;
      if (d != null) {
        byDue.putIfAbsent(isoDate(d), () => []).add(h);
      }
    }
    return (byId: byId, byDue: byDue);
  }

  /// groupByDue == false — ДЗ, заданные на уроке (sourceHomeworkIds → byId);
  /// true — что сдать к этой дате по предмету (byDue + фильтр по subjectId).
  static ({
    List<String> texts,
    List<int> ids,
    List<HomeworkAttachment> attachments,
  })
  forLesson({
    required int? subjectId,
    required DateTime date,
    required List<int> sourceHomeworkIds,
    required Map<int, Homework> byId,
    required Map<String, List<Homework>> byDue,
    required bool groupByDue,
  }) {
    if (!groupByDue) {
      final texts = <String>[];
      final ids = <int>[];
      final seen = <String>{};
      final attachments = <HomeworkAttachment>[];
      for (final id in sourceHomeworkIds) {
        final hw = byId[id];
        if (hw == null) continue;
        if (!isMeaningful(hw.description)) continue;
        texts.add(hw.description.trim());
        ids.add(hw.id);
        for (final a in hw.attachments) {
          if (seen.add(a.url)) attachments.add(a);
        }
      }
      return (texts: texts, ids: ids, attachments: attachments);
    }

    if (subjectId == null) {
      return (texts: const [], ids: const [], attachments: const []);
    }

    final due = byDue[isoDate(date)] ?? const [];
    final texts = <String>[];
    final ids = <int>[];
    final seen = <String>{};
    final attachments = <HomeworkAttachment>[];

    for (final hw in due) {
      if (hw.subjectId != subjectId) continue;
      if (!isMeaningful(hw.description)) continue;
      texts.add(hw.description.trim());
      ids.add(hw.id);
      for (final a in hw.attachments) {
        if (seen.add(a.url)) attachments.add(a);
      }
    }
    return (texts: texts, ids: ids, attachments: attachments);
  }
}
