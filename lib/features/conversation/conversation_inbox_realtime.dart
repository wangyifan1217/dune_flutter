import '../nova/nova_history_utils.dart';
import 'comm_unread_notifier.dart';
import 'conversation_mention_utils.dart';
import 'conversation_models.dart';
import 'conversation_realtime_service.dart';
import 'inbox_hidden_storage.dart';

/// 与 WebView `applyConvEvent` 对齐的 C1 列表增量更新。
abstract final class ConversationInboxRealtime {
  static ConversationRealtimeEventLike fromEvent(ConversationRealtimeEvent event) {
    final raw = _asStringKeyMap(event.raw);
    final msgRaw = raw['message'];
    return ConversationRealtimeEventLike(
      type: event.type,
      raw: raw,
      conversationId: event.conversationId,
      message: msgRaw is Map ? _asStringKeyMap(msgRaw) : null,
    );
  }

  static Map<String, dynamic> _asStringKeyMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static List<NativeConversation> applyEvent({
    required List<NativeConversation> items,
    required ConversationRealtimeEventLike event,
    required int selfUserId,
    String? selfDisplayName,
    bool activeOnChatScreen = false,
  }) {
    final convId = event.conversationId ?? 0;
    if (convId <= 0) return items;

    final index = items.indexWhere((c) => c.id == convId);
    if (index < 0) return items;

    if (event.type == 'read') {
      final userId = (event.raw['userId'] as num?)?.toInt() ?? 0;
      if (userId != selfUserId) return items;
      final copy = items.toList(growable: true);
      copy[index] = _copyConversation(copy[index], unreadCount: 0);
      return copy;
    }

    final preview = _previewForEvent(
      event,
      conv: items[index],
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
    if (preview == null) return items;

    final at = _timestampForEvent(event);
    final fromPeer = _isFromPeer(event, selfUserId);
    final conv = items[index];
    final mentionHit = ConversationMentionUtils.eventMentionsMe(
      event: event,
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
    final isMutedGroup = CommUnreadNotifier.isMutedGroup(conv);
    final isMessageEvent = event.type == 'message' || event.type == 'system_flow';
    final bumpUnread = !activeOnChatScreen &&
        isMessageEvent &&
        ((fromPeer && !isMutedGroup) || mentionHit);

    final copy = items.toList(growable: true);
    final old = copy[index];
    copy[index] = _copyConversation(
      old,
      preview: preview.text,
      updatedAt: at ?? old.updatedAt,
      unreadCount: bumpUnread ? old.unreadCount + 1 : old.unreadCount,
    );

    copy.sort((a, b) {
      final ap = a.pinned ? 1 : 0;
      final bp = b.pinned ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      return b.sortTimestamp.compareTo(a.sortTimestamp);
    });
    return copy;
  }

  static bool needsFullRefresh(ConversationRealtimeEventLike event, List<NativeConversation> items) {
    final convId = event.conversationId ?? 0;
    if (convId <= 0) return true;
    if (items.every((c) => c.id != convId)) return true;
    if (event.type == 'conversation_updated') return true;
    return false;
  }

  static _PreviewPatch? _previewForEvent(
    ConversationRealtimeEventLike event, {
    required NativeConversation conv,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    switch (event.type) {
      case 'message':
      case 'system_flow':
        final msg = event.message;
        if (msg == null) return null;
        return _PreviewPatch(_messagePreview(msg, conv: conv, selfUserId: selfUserId, selfDisplayName: selfDisplayName));
      case 'message_recalled':
        var preview = (event.raw['preview'] ?? '消息已撤回').toString();
        if (conv.isGroup || conv.isWorkgroupApproval) {
          final name = (event.raw['recalledByName'] ??
                  event.raw['recalledByDisplayName'] ??
                  '')
              .toString();
          if (name.isNotEmpty) preview = '$name: $preview';
        }
        return _PreviewPatch(preview);
      case 'message_updated':
        final msg = event.message;
        if (msg == null) return null;
        return _PreviewPatch(_messagePreview(msg, conv: conv, selfUserId: selfUserId, selfDisplayName: selfDisplayName));
      case 'message_deleted':
        return const _PreviewPatch('消息已删除');
      case 'conversation_updated':
        final body = (event.raw['lastMessageBodyText'] ?? event.raw['preview'] ?? '').toString();
        if (body.isNotEmpty) return _PreviewPatch(body);
        return null;
      default:
        return null;
    }
  }

  static String _messagePreview(
    Map<String, dynamic> msg, {
    required NativeConversation conv,
    required int selfUserId,
    String? selfDisplayName,
  }) {
    final kind = (msg['kind'] ?? '').toString().toUpperCase();
    final body = (msg['bodyText'] ?? '').toString();
    var sender = '';
    final senderMap = msg['sender'];
    if (senderMap is Map<String, dynamic>) {
      sender = (senderMap['displayName'] ?? '').toString();
      final sid = (senderMap['userId'] as num?)?.toInt() ?? 0;
      if (sender.isEmpty && sid == selfUserId) sender = selfDisplayName ?? '';
    }
    final prefix = (conv.isGroup || conv.isWorkgroupApproval) && sender.isNotEmpty ? '$sender: ' : '';
    if (kind == 'IMAGE') return '$prefix[图片]';
    if (kind == 'FILE') return '$prefix[文件]';
    if (kind == 'AUDIO') return '$prefix[语音]';
    if (kind == 'SYSTEM_FLOW') return body.isEmpty ? '$prefix[系统消息]' : '$prefix$body';
    if (body.isNotEmpty) return conv.isPrivate ? body : '$prefix$body';
    return body.isEmpty ? '[消息]' : body;
  }

  static DateTime? _timestampForEvent(ConversationRealtimeEventLike event) {
    final msg = event.message;
    if (msg != null) {
      return parseNovaDateTime(msg['createdAt']);
    }
    return parseNovaDateTime(
      event.raw['updatedAt'] ?? event.raw['lastMessageAt'] ?? event.raw['previewAt'],
    );
  }

  static bool _isFromPeer(ConversationRealtimeEventLike event, int selfUserId) {
    final msg = event.message;
    if (msg == null) return false;
    final sender = msg['sender'];
    if (sender is Map<String, dynamic>) {
      final uid = (sender['userId'] as num?)?.toInt() ?? 0;
      return uid > 0 && uid != selfUserId;
    }
    final sid = (msg['senderUserId'] as num?)?.toInt() ?? 0;
    return sid > 0 && sid != selfUserId;
  }

  static NativeConversation _copyConversation(
    NativeConversation c, {
    String? preview,
    DateTime? updatedAt,
    int? unreadCount,
  }) {
    return NativeConversation(
      id: c.id,
      kind: c.kind,
      title: c.title,
      unreadCount: unreadCount ?? c.unreadCount,
      preview: preview ?? c.preview,
      updatedAt: updatedAt ?? c.updatedAt,
      peerUserId: c.peerUserId,
      peerDisplayName: c.peerDisplayName,
      memberCount: c.memberCount,
      muted: c.muted,
      pinned: c.pinned,
      businessType: c.businessType,
      peerDepartment: c.peerDepartment,
      peerRoleLabel: c.peerRoleLabel,
      peerAvatarPreset: c.peerAvatarPreset,
      peerAvatarObjectKey: c.peerAvatarObjectKey,
      avatarMembers: c.avatarMembers,
      dissolved: c.dissolved,
      membershipStatus: c.membershipStatus,
      assistantGenerating: c.assistantGenerating,
      assistantGeneratingStatus: c.assistantGeneratingStatus,
    );
  }
}

class _PreviewPatch {
  const _PreviewPatch(this.text);
  final String text;
}
