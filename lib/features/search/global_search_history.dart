import 'package:shared_preferences/shared_preferences.dart';

class GlobalSearchHistoryStore {
  GlobalSearchHistoryStore._();

  static const _key = 'dunes_global_search_history_v1';
  static const maxItems = 8;

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList(_key) ?? const <String>[];
      return rows
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(maxItems)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<List<String>> add(String query) async {
    final next = query.trim();
    if (next.isEmpty) return load();
    final current = [...await load()];
    current.removeWhere((e) => e.toLowerCase() == next.toLowerCase());
    current.insert(0, next);
    final saved = current.take(maxItems).toList(growable: false);
    await _persist(saved);
    return saved;
  }

  static Future<List<String>> remove(String query) async {
    final current = [...await load()]
      ..removeWhere((e) => e == query);
    await _persist(current);
    return current;
  }

  static Future<List<String>> clear() async {
    await _persist(const <String>[]);
    return const <String>[];
  }

  static Future<void> _persist(List<String> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, rows);
    } catch (_) {}
  }
}
