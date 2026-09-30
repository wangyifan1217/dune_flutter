import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 本机记住「标志未读」。服务端还没带这个字段时，刷新列表也不会丢掉。
abstract final class MarkedUnreadStorage {
  static String _key(int userId) => 'dunes_marked_unread_v1_$userId';

  static Future<Set<int>> load(int userId) async {
    if (userId <= 0) return <int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null || raw.isEmpty) return <int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      return decoded.map((item) => (item as num).toInt()).where((id) => id > 0).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<void> save(int userId, Set<int> ids) async {
    if (userId <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = ids.toList()..sort();
      await prefs.setString(_key(userId), jsonEncode(list));
    } catch (_) {}
  }
}
