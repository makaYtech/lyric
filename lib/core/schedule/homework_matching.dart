import '../../models/homework.dart';
import '../../models/homework_attachment.dart';
import '../util/date_time.dart';

/// Матчинг ДЗ к урокам. Одна и та же логика используется:
///   • в ScheduleService — при сетевом запросе расписания;
///   • в ScheduleRepository — при пересборке из кэша (когда юзер
///     переключает режим группировки без обращения к серверу).
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

  /// Построить мапы из плоского годового списка ДЗ:
  ///   byId  — homework.id → Homework (для режима «задано в этот день»);
  ///   byDue — iso(dueDate) → список Homework (для режима дедлайна).
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

  /// Собрать блок «ДЗ» для одного урока.
  ///
  ///   • groupByDue == false — то, что задали на этом уроке:
  ///     sourceHomeworkIds (id из homeworks_to_give) → byId.
  ///   • groupByDue == true — то, что надо сдать к этой дате и по этому
  ///     предмету: byDue[iso(date)] с фильтром по subjectId.
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
