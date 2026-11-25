import '../../core/util/json.dart';
import '../../core/util/labels.dart';
import './lesson.dart';

class DaySchedule {
  final DateTime date;
  final List<Lesson> lessons;

  const DaySchedule({required this.date, required this.lessons});

  String get weekdayName => kWeekdaysFull[date.weekday - 1];

  String get dateLabel => '${date.day} ${kMonthsGenitive[date.month - 1]}';

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    return DaySchedule(
      date: DateTime.parse(json['date'] as String),
      lessons: json.mapList('lessons').map(Lesson.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'lessons': lessons.map((l) => l.toJson()).toList(),
  };
}
