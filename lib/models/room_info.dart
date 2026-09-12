/// Один элемент из /core/api/rooms — тут есть человеческий "number"
/// кабинета, которого нет в schedule_items (там только room_id/room_name).
class RoomInfo {
  final int id;
  final String name;
  final String number;

  const RoomInfo({required this.id, required this.name, required this.number});

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    number: json['number']?.toString() ?? '',
  );
}