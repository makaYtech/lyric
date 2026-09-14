import 'package:shared_preferences/shared_preferences.dart';

import '../../services/myschool/myschool_tokens.dart';

/// Персистентное хранилище токенов «Моей школы».
class MySchoolTokenStorage {
  static const _accKey = 'myschool_acc_t';
  static const _userKey = 'myschool_u';
  static const _studentKey = 'myschool_student_id';

  Future<MySchoolTokens?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final acc = prefs.getString(_accKey);
    final u = prefs.getString(_userKey);
    final sid = prefs.getString(_studentKey);
    if (acc == null || u == null || sid == null) return null;
    final tokens = MySchoolTokens(accT: acc, userId: u, studentId: sid);
    if (tokens.isExpired) return null;
    return tokens;
  }

  Future<void> save(MySchoolTokens tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accKey, tokens.accT);
    await prefs.setString(_userKey, tokens.userId);
    await prefs.setString(_studentKey, tokens.studentId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accKey);
    await prefs.remove(_userKey);
    await prefs.remove(_studentKey);
  }
}