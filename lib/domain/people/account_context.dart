/// Профили из ответа `/acl/api/users?ids=...&pid=...`.
///
/// У ученика в `profiles[]` один профиль с `type: student`, у родителя —
/// `type: parent` и `children_profile_ids`.
class EposAccountProfile {
  final int id;
  final String type;
  final int? userId;
  final List<int> childrenProfileIds;
  final String? schoolShortname;

  const EposAccountProfile({
    required this.id,
    required this.type,
    this.userId,
    this.childrenProfileIds = const [],
    this.schoolShortname,
  });

  bool get isParent => type == 'parent';
  bool get isStudent => type == 'student';

  static EposAccountProfile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = _asInt(map['id']);
    if (id == null) return null;

    final childrenRaw = map['children_profile_ids'];
    final children = childrenRaw is List
        ? childrenRaw.map(_asInt).whereType<int>().toList()
        : <int>[];

    return EposAccountProfile(
      id: id,
      type: (map['type'] as String?)?.trim().toLowerCase() ?? 'unknown',
      userId: _asInt(map['user_id']),
      childrenProfileIds: children,
      schoolShortname: map['school_shortname'] as String?,
    );
  }
}

class EposAccountContext {
  final List<EposAccountProfile> profiles;

  const EposAccountContext({required this.profiles});

  static const empty = EposAccountContext(profiles: []);

  bool get isParent => profiles.any((p) => p.isParent);
  bool get isStudent => profiles.any((p) => p.isStudent);

  /// Есть ли вообще профили. Пусто = ответ не распознан.
  bool get isEmpty => profiles.isEmpty;

  /// user_id владельца аккаунта — из любого профиля, где он заполнен.
  int? get ownerUserId {
    for (final profile in profiles) {
      if (profile.userId != null) return profile.userId;
    }
    return null;
  }

  EposAccountProfile? get parent {
    for (final profile in profiles) {
      if (profile.isParent) return profile;
    }
    return null;
  }

  List<int> get childrenProfileIds {
    final result = <int>[];
    for (final profile in profiles) {
      if (!profile.isParent) continue;
      for (final id in profile.childrenProfileIds) {
        if (!result.contains(id)) result.add(id);
      }
    }
    return result;
  }

  /// Ответ — List пользователей, Map с data/users или Map одного пользователя.
  static EposAccountContext fromUsersResponse(dynamic raw) {
    dynamic root = raw;
    if (root is Map) {
      root = root['data'] ?? root['users'] ?? root;
    }

    final profiles = <EposAccountProfile>[];
    void addFrom(Object? user) {
      if (user is! Map) return;
      final list = user['profiles'];
      if (list is! List) return;
      for (final item in list) {
        final parsed = EposAccountProfile.tryParse(item);
        if (parsed != null) profiles.add(parsed);
      }
    }

    if (root is List) {
      for (final user in root) {
        addFrom(user);
      }
    } else {
      addFrom(root);
    }

    return EposAccountContext(profiles: profiles);
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
