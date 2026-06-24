import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists Nova / KB WebView localStorage across app rebuilds (Chrome blob iframe,
/// WebView reload). Auth credentials still come from [AuthSession.novaLocalStorage].
abstract final class NovaWebStorage {
  static const _keyPrefix = 'dunes_nova_web_state_v1_';

  static String _storageKey(int userId) => '$_keyPrefix$userId';

  static Future<Map<String, String>> load(int userId) async {
    if (userId <= 0) return const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey(userId));
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value != null) {
          out[key] = value.toString();
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> save(int userId, Map<String, dynamic> data) async {
    if (userId <= 0 || data.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, String>{};
      data.forEach((key, value) {
        if (value == null) return;
        final text = value.toString();
        if (text.isEmpty) return;
        if (_shouldPersistKey(key.toString())) out[key.toString()] = text;
      });
      if (out.isEmpty) return;
      await prefs.setString(_storageKey(userId), jsonEncode(out));
    } catch (_) {}
  }

  /// 合并写入，供原生云枢会话缓存 dunes_nova_msgs_* 等键。
  static Future<Map<String, String>> merge(int userId, Map<String, dynamic> patch) async {
    if (userId <= 0 || patch.isEmpty) return load(userId);
    final existing = await load(userId);
    final merged = Map<String, String>.from(existing);
    patch.forEach((key, value) {
      if (value == null) return;
      final text = value.toString();
      if (!_shouldPersistKey(key)) return;
      if (text.isEmpty) {
        merged.remove(key);
        return;
      }
      merged[key] = text;
    });
    await save(userId, Map<String, dynamic>.from(merged));
    return merged;
  }

  /// 删除指定键，对齐 WebView `localStorage.removeItem`。
  static Future<Map<String, String>> removeKeys(int userId, Iterable<String> keys) async {
    if (userId <= 0) return load(userId);
    final existing = await load(userId);
    final merged = Map<String, String>.from(existing);
    var changed = false;
    for (final key in keys) {
      if (merged.remove(key) != null) changed = true;
    }
    if (!changed) return merged;
    await save(userId, Map<String, dynamic>.from(merged));
    return merged;
  }

  static Future<void> clear(int userId) async {
    if (userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey(userId));
  }

  static bool _shouldPersistKey(String key) {
    if (_exactKeys.contains(key)) return true;
    for (final prefix in _prefixKeys) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  static const _exactKeys = {
    'dunes_nova_conv_id',
    'dunes_nova_owner_uid',
    'dunes_nova_profile_session',
    'dunes_nova_local_history',
    'dunes_nova_chat_model',
    'dunes_nova_view_since',
    'dunes_nova_history_sync_queue',
    'dunes_ai_local_purge_v',
    'dunes_kb_local_history',
    'dunes_kb_conv_id',
    'dunes_kb_last_preview',
  };

  static const _prefixKeys = [
    'dunes_nova_msgs_',
    'dunes_kb_msgs_',
    'dunes_nova_generating_',
    'dunes_nova_stream_draft_',
  ];
}
