import '../../core/util/json.dart';

/// Один элемент из /core/api/rooms: человеческий номер кабинета, которого
/// нет в schedule_items (там только room_id/room_name).
class RoomInfo {
  final int id;
  final String name;
  final String number;

  const RoomInfo({required this.id, required this.name, required this.number});

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    id: json.intOr('id', 0),
    name: json.str('name'),
    number: json['number']?.toString() ?? '',
  );
}
