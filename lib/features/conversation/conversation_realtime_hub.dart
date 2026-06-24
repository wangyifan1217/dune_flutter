import 'dart:async';

import '../auth/auth_session.dart';
import 'conversation_realtime_service.dart';

/// 全局共享的 IM 实时连接，避免各页面各自 connect/disconnect 导致在线状态丢失。
class ConversationRealtimeHub {
  ConversationRealtimeHub._();

  static final ConversationRealtimeHub instance = ConversationRealtimeHub._();

  ConversationRealtimeService? _service;
  int? _userId;

  ConversationRealtimeService of(AuthSession session) {
    if (_service == null || _userId != session.userId) {
      unawaited(_service?.close());
      _service = ConversationRealtimeService(session: session);
      _userId = session.userId;
    }
    return _service!;
  }

  Future<void> dispose() async {
    await _service?.close();
    _service = null;
    _userId = null;
  }
}
