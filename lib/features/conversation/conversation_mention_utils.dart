import 'dart:convert';

import 'conversation_realtime_service.dart';
import 'inbox_hidden_storage.dart';

/// 与 WebView `eventMentionsMe` / `parseEventPayload` 对齐。
abstract final class ConversationMentionUtils {
  static bool eventMentionsMe({
    required ConversationRealtimeEventLike event,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    if (selfUserId <= 0) return false;
    final msg = event.message;
    if (msg == null) return false;

    final payload = _parsePayload(msg['payload']);
    if (payload['mentionAll'] == true || payload['atAll'] == true || payload['isAtAll'] == true) {
      return true;
    }

    for (final key in ['mentionUserIds', 'mentionedUserIds', 'atUserIds', 'mentions']) {
      if (_listContainsUserId(payload[key], selfUserId)) return true;
    }

    final body = (msg['bodyText'] ?? '').toString();
    final mine = (selfDisplayName ?? '').trim();
    if (body.contains('@所有人')) return true;
    if (mine.isNotEmpty && body.contains('@$mine')) return true;
    return false;
  }

  static bool eventMentionsMeFromRealtime({
    required ConversationRealtimeEvent event,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    final raw = event.raw;
    final msgRaw = raw['message'];
    return eventMentionsMe(
      event: ConversationRealtimeEventLike(
        type: event.type,
        raw: Map<String, dynamic>.from(event.raw),
        conversationId: event.conversationId,
        message: msgRaw is Map ? Map<String, dynamic>.from(msgRaw) : null,
      ),
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
  }

  static Map<String, dynamic> _parsePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  static bool _listContainsUserId(dynamic raw, int selfUserId) {
    if (raw == null) return false;
    final items = raw is List ? raw : <dynamic>[raw];
    for (final item in items) {
      if (item is Map) {
        final uid = (item['userId'] as num?)?.toInt() ?? (item['id'] as num?)?.toInt() ?? 0;
        if (uid == selfUserId) return true;
      } else {
        final uid = (item as num?)?.toInt() ?? 0;
        if (uid == selfUserId) return true;
      }
    }
    return false;
  }
}
