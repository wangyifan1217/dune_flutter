import 'conversation_realtime_service.dart';

/// 与 WebView `im_chat_injection.dart` 中 `rtEventKey` / `consumeRtEvent` 对齐。
class ConversationRealtimeDedup {
  final Map<String, int> _seen = <String, int>{};

  bool consume(ConversationRealtimeEvent event) {
    final key = _eventKey(event);
    if (key.isEmpty) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _seen[key];
    if (prev != null && now - prev < 60000) return false;
    _seen[key] = now;
    if (_seen.length > 200) {
      _seen.removeWhere((_, at) => now - at > 120000);
    }
    return true;
  }

  void markSeen(ConversationRealtimeEvent event) {
    final key = _eventKey(event);
    if (key.isEmpty) return;
    _seen[key] = DateTime.now().millisecondsSinceEpoch;
  }

  String _eventKey(ConversationRealtimeEvent event) {
    final data = event.raw;
    final type = event.type;
    if (type == 'message' || type == 'system_flow') {
      final msg = data['message'];
      if (msg is Map<String, dynamic>) {
        final id = (msg['id'] as num?)?.toInt();
        if (id != null && id > 0) return '$type:$id';
      }
    }
    if (type == 'message_recalled') {
      final id = (data['messageId'] as num?)?.toInt() ??
          ((data['message'] is Map<String, dynamic>)
              ? ((data['message'] as Map<String, dynamic>)['id'] as num?)?.toInt()
              : null);
      if (id != null && id > 0) return 'recall:$id';
    }
    if (type == 'message_updated') {
      final msg = data['message'];
      if (msg is Map<String, dynamic>) {
        final id = (msg['id'] as num?)?.toInt();
        if (id != null && id > 0) return 'updated:$id';
      }
    }
    if (type == 'message_deleted') {
      final id = (data['messageId'] as num?)?.toInt();
      if (id != null && id > 0) return 'deleted:$id';
    }
    if (type == 'read') {
      final convId = event.conversationId ?? 0;
      final userId = (data['userId'] as num?)?.toInt() ?? 0;
      final lastRead = (data['lastReadMessageId'] as num?)?.toInt() ?? 0;
      if (convId > 0 && userId > 0) return 'read:$convId:$userId:$lastRead';
    }
    if (type == 'notification') {
      final title = (data['title'] ?? '').toString();
      final body = (data['body'] ?? '').toString();
      if (title.isNotEmpty) return 'notification:$title:$body';
    }
    return '';
  }
}
