import 'dart:convert';

import 'conversation_realtime_service.dart';
import 'inbox_hidden_storage.dart';

enum ConversationMentionKind { none, me, atAll }

/// 与 WebView `eventMentionsMe` / `parseEventPayload` 对齐。
abstract final class ConversationMentionUtils {
  static bool eventMentionsMe({
    required ConversationRealtimeEventLike event,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    return eventMentionKind(
          event: event,
          selfUserId: selfUserId,
          selfDisplayName: selfDisplayName,
        ) !=
        ConversationMentionKind.none;
  }

  static ConversationMentionKind eventMentionKind({
    required ConversationRealtimeEventLike event,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    final msg = event.message;
    if (msg == null) return ConversationMentionKind.none;
    return mentionKindFromMessage(
      msg: msg,
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
  }

  static ConversationMentionKind mentionKindFromMessage({
    required Map<String, dynamic> msg,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    if (selfUserId <= 0) return ConversationMentionKind.none;

    final payload = _parsePayload(msg['payload']);
    final body = (msg['bodyText'] ?? '').toString();
    final mine = (selfDisplayName ?? '').trim();
    final atAll =
        payload['mentionAll'] == true ||
        payload['atAll'] == true ||
        payload['isAtAll'] == true ||
        body.contains('@所有人');
    var atMeById = false;
    for (final key in [
      'mentionUserIds',
      'mentionedUserIds',
      'atUserIds',
      'mentions',
    ]) {
      if (_listContainsUserId(payload[key], selfUserId)) {
        atMeById = true;
        break;
      }
    }
    final atMeByName = mine.isNotEmpty && body.contains('@$mine');
    // @所有人 发送时 mentionUserIds 常会带上全员，不能因此显示 [@了你]。
    if (atMeByName || (atMeById && !atAll)) {
      return ConversationMentionKind.me;
    }
    if (atAll) return ConversationMentionKind.atAll;
    return ConversationMentionKind.none;
  }

  static bool unreadMentionFromJson(Map<String, dynamic> raw) {
    if (raw['hasUnreadMention'] == true ||
        raw['mentionedMe'] == true ||
        raw['atMe'] == true) {
      return true;
    }
    return ((raw['unreadMentionCount'] as num?)?.toInt() ?? 0) > 0;
  }

  static bool unreadAtAllFromJson(Map<String, dynamic> raw) {
    if (raw['hasUnreadAtAll'] == true ||
        raw['mentionedAll'] == true ||
        raw['atAll'] == true) {
      return true;
    }
    return ((raw['unreadAtAllCount'] as num?)?.toInt() ?? 0) > 0;
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
