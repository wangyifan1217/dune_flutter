import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class InboxHiddenEntry {
  const InboxHiddenEntry({required this.at, required this.permanent});

  final int at;
  final bool permanent;

  factory InboxHiddenEntry.fromJson(Object? raw) {
    if (raw is num) {
      return InboxHiddenEntry(at: raw.toInt(), permanent: false);
    }
    if (raw is Map) {
      return InboxHiddenEntry(
        at: (raw['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        permanent: raw['permanent'] == true,
      );
    }
    return InboxHiddenEntry(at: DateTime.now().millisecondsSinceEpoch, permanent: false);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'at': at,
    'permanent': permanent,
  };
}

/// 与 WebView `mobile_injection.dart` 中 `HIDDEN_C1_KEY` 对齐。
abstract final class InboxHiddenStorage {
  static const _key = 'dunes_c1_hidden_conversations_v1';

  static Future<Map<String, InboxHiddenEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, InboxHiddenEntry>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, InboxHiddenEntry>{};
      final out = <String, InboxHiddenEntry>{};
      decoded.forEach((key, value) {
        out[key.toString()] = InboxHiddenEntry.fromJson(value);
      });
      return out;
    } catch (_) {
      return <String, InboxHiddenEntry>{};
    }
  }

  static Future<void> save(Map<String, InboxHiddenEntry> map) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      map.map((key, value) => MapEntry(key, value.toJson())),
    );
    await prefs.setString(_key, encoded);
  }

  static Future<void> hide(int conversationId, {bool permanent = false}) async {
    if (conversationId <= 0) return;
    final map = await load();
    map[conversationId.toString()] = InboxHiddenEntry(
      at: DateTime.now().millisecondsSinceEpoch,
      permanent: permanent,
    );
    await save(map);
  }

  static Future<void> unhide(int conversationId) async {
    if (conversationId <= 0) return;
    final map = await load();
    final entry = map[conversationId.toString()];
    if (entry == null || entry.permanent) return;
    map.remove(conversationId.toString());
    await save(map);
  }

  static Future<void> upgradeDissolved(List<int> dissolvedIds) async {
    if (dissolvedIds.isEmpty) return;
    final map = await load();
    var changed = false;
    for (final id in dissolvedIds) {
      final key = id.toString();
      final entry = map[key];
      if (entry == null || entry.permanent) continue;
      map[key] = InboxHiddenEntry(at: entry.at, permanent: true);
      changed = true;
    }
    if (changed) await save(map);
  }
}

bool isConversationHidden(Map<String, InboxHiddenEntry> map, int conversationId) {
  return map.containsKey(conversationId.toString());
}

bool isConversationPermanentlyHidden(Map<String, InboxHiddenEntry> map, int conversationId) {
  return map[conversationId.toString()]?.permanent ?? false;
}

bool shouldUnhideFromRealtimeEvent(
  ConversationRealtimeEventLike event,
  Map<String, InboxHiddenEntry> hidden,
  int selfUserId,
) {
  if (event.type != 'message' && event.type != 'system_flow') return false;
  final convId = event.conversationId ?? 0;
  if (convId <= 0 || !isConversationHidden(hidden, convId)) return false;
  if (isConversationPermanentlyHidden(hidden, convId)) return false;
  final msg = event.message;
  if (msg == null) return false;
  final kind = (msg['kind'] ?? '').toString().toUpperCase();
  if (kind.startsWith('SYSTEM')) return false;
  final senderId = _senderUserId(msg);
  return senderId > 0 && senderId != selfUserId;
}

int _senderUserId(Map<String, dynamic> msg) {
  final sender = msg['sender'];
  if (sender is Map<String, dynamic>) {
    return (sender['userId'] as num?)?.toInt() ?? 0;
  }
  return (msg['senderUserId'] as num?)?.toInt() ?? 0;
}

/// 轻量事件视图，供 inbox 增量刷新使用。
class ConversationRealtimeEventLike {
  const ConversationRealtimeEventLike({
    required this.type,
    required this.raw,
    this.conversationId,
    this.message,
  });

  final String type;
  final Map<String, dynamic> raw;
  final int? conversationId;
  final Map<String, dynamic>? message;
}
