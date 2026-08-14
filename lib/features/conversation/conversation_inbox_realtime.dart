import '../nova/nova_history_utils.dart';
import 'comm_unread_notifier.dart';
import 'conversation_mention_utils.dart';
import 'conversation_models.dart';
import 'conversation_realtime_service.dart';
import 'inbox_hidden_storage.dart';

/// 与 WebView `applyConvEvent` 对齐的 C1 列表增量更新。
abstract final class ConversationInboxRealtime {
  static ConversationRealtimeEventLike fromEvent(
    ConversationRealtimeEvent event,
  ) {
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
      copy[index] = copyConversation(copy[index], unreadCount: 0);
      return copy;
    }

    final conv = items[index];
    // 编辑/删除历史消息不应改写列表预览与排序时间（否则会显示成「不是最后一条」）。
    if (event.type == 'message_updated' &&
        !_isEditingCurrentLatestMessage(event, conv)) {
      return items;
    }

    final preview = _previewForEvent(
      event,
      conv: conv,
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
    // message_updated：只改预览文案，不改 sortTimestamp。
    final at = event.type == 'message_updated'
        ? null
        : _timestampForEvent(event);
    if (preview == null && at == null && event.type != 'conversation_updated') {
      return items;
    }

    final fromPeer = _isFromPeer(event, selfUserId);
    final mentionHit = ConversationMentionUtils.eventMentionsMe(
      event: event,
      selfUserId: selfUserId,
      selfDisplayName: selfDisplayName,
    );
    final isMutedGroup = CommUnreadNotifier.isMutedGroup(conv);
    final isMessageEvent =
        event.type == 'message' || event.type == 'system_flow';
    final bumpUnread =
        !activeOnChatScreen &&
        isMessageEvent &&
        ((fromPeer && !isMutedGroup) || mentionHit);

    final copy = items.toList(growable: true);
    final old = copy[index];
    // conversation_updated 携带服务端未读数时以服务端为准
    //（任务助手等系统消息 sender 为空，客户端无法靠 fromPeer 判断加一）。
    final serverUnread = event.type == 'conversation_updated'
        ? (event.raw['unreadCount'] as num?)?.toInt()
        : null;
    // 正在看该会话：不累加，并清掉残留未读角标。
    final nextUnread = activeOnChatScreen
        ? 0
        : (serverUnread ??
              (bumpUnread ? old.unreadCount + 1 : old.unreadCount));
    copy[index] = copyConversation(
      old,
      preview: preview?.text,
      updatedAt: at ?? old.updatedAt,
      unreadCount: nextUnread,
      title: _titleForEvent(event, old),
    );

    copy.sort((a, b) {
      final ap = a.pinned ? 1 : 0;
      final bp = b.pinned ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      return b.sortTimestamp.compareTo(a.sortTimestamp);
    });
    return copy;
  }

  static bool needsFullRefresh(
    ConversationRealtimeEventLike event,
    List<NativeConversation> items,
  ) {
    final convId = event.conversationId ?? 0;
    if (convId <= 0) return true;
    if (items.every((c) => c.id != convId)) return true;
    if (event.type == 'conversation_updated') {
      final raw = event.raw;
      if (raw['dissolved'] == true || raw['isDissolved'] == true) return true;
      if (raw['avatarMembers'] != null) return true;
      if (raw['peerAvatarUrl'] != null ||
          raw['peerAvatarObjectKey'] != null ||
          raw['peerAvatarPreset'] != null) {
        return true;
      }
      return false;
    }
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
        return _PreviewPatch(
          _messagePreview(
            msg,
            conv: conv,
            selfUserId: selfUserId,
            selfDisplayName: selfDisplayName,
          ),
        );
      case 'message_recalled':
        var preview = (event.raw['preview'] ?? '消息已撤回').toString();
        if (conv.isGroup || conv.isWorkgroupApproval) {
          final name =
              (event.raw['recalledByName'] ??
                      event.raw['recalledByDisplayName'] ??
                      '')
                  .toString();
          if (name.isNotEmpty) preview = '$name: $preview';
        }
        return _PreviewPatch(preview);
      case 'message_updated':
        final msg = event.message;
        if (msg == null) return null;
        return _PreviewPatch(
          _messagePreview(
            msg,
            conv: conv,
            selfUserId: selfUserId,
            selfDisplayName: selfDisplayName,
          ),
        );
      case 'message_deleted':
        return const _PreviewPatch('消息已删除');
      case 'conversation_updated':
        final body =
            (event.raw['lastMessageBodyText'] ??
                    event.raw['lastMessagePreview'] ??
                    event.raw['preview'] ??
                    '')
                .toString();
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
    final prefix =
        (conv.isGroup || conv.isWorkgroupApproval) && sender.isNotEmpty
        ? '$sender: '
        : '';
    if (kind == 'IMAGE') return '$prefix[图片]';
    if (kind == 'FILE') return '$prefix[文件]';
    if (kind == 'AUDIO') return '$prefix[语音]';
    if (kind == 'SYSTEM_FLOW') {
      return body.isEmpty ? '$prefix[系统消息]' : '$prefix$body';
    }
    if (kind == 'WEEKLY_SUMMARY') {
      return body.isEmpty ? '$prefix[一周小结]' : '$prefix$body';
    }
    if (kind == 'RECONCILIATION' || kind == 'RECONCILIATION_ASSISTANT') {
      return body.isEmpty ? '$prefix每日对账 · 待你确认' : '$prefix$body';
    }
    if (kind == 'RECONCILIATION_REMIND') {
      return body.isEmpty ? '$prefix对账催办' : '$prefix$body';
    }
    if (body.isNotEmpty) return conv.isPrivate ? body : '$prefix$body';
    return body.isEmpty ? '[消息]' : body;
  }

  static DateTime? _timestampForEvent(ConversationRealtimeEventLike event) {
    final msg = event.message;
    if (msg != null) {
      return parseNovaDateTime(msg['createdAt']);
    }
    return parseNovaDateTime(
      event.raw['updatedAt'] ??
          event.raw['lastMessageAt'] ??
          event.raw['previewAt'],
    );
  }

  /// 工作台编辑消息时：仅当被编辑的是当前列表对应的最新消息才刷新预览。
  static bool _isEditingCurrentLatestMessage(
    ConversationRealtimeEventLike event,
    NativeConversation conv,
  ) {
    final msg = event.message;
    if (msg == null) return false;
    final msgAt = parseNovaDateTime(msg['createdAt']);
    final current = conv.updatedAt;
    if (msgAt == null) return false;
    if (current == null) return true;
    // 允许相等（编辑当前最后一条）；更早的消息直接忽略。
    return !msgAt.isBefore(current);
  }

  static bool _isFromPeer(ConversationRealtimeEventLike event, int selfUserId) {
    final msg = event.message;
    if (msg == null) return false;
    final kind = (msg['kind'] ?? '').toString().toUpperCase();
    if (kind == 'ROBOT_REPLY' || isIncomingAssistantMessageKind(kind)) {
      return true;
    }
    final sender = msg['sender'];
    if (sender is Map<String, dynamic>) {
      final uid = (sender['userId'] as num?)?.toInt() ?? 0;
      return uid > 0 && uid != selfUserId;
    }
    final sid = (msg['senderUserId'] as num?)?.toInt() ?? 0;
    return sid > 0 && sid != selfUserId;
  }

  /// 助手/系统推送没有真人 sender，但仍应计未读。
  static bool isIncomingAssistantMessageKind(String kind) {
    switch (kind.trim().toUpperCase()) {
      case 'RECONCILIATION':
      case 'RECONCILIATION_REMIND':
      case 'RECONCILIATION_ASSISTANT':
      case 'WEEKLY_SUMMARY':
      case 'APPROVAL_ASSISTANT':
      case 'TASK_ASSISTANT':
        return true;
      default:
        return false;
    }
  }

  static String? _titleForEvent(
    ConversationRealtimeEventLike event,
    NativeConversation current,
  ) {
    if (event.type != 'conversation_updated') return null;
    final title = (event.raw['title'] ?? event.raw['peerDisplayName'] ?? '')
        .toString()
        .trim();
    return title.isEmpty ? null : title;
  }

  static NativeConversation copyConversation(
    NativeConversation c, {
    String? preview,
    DateTime? updatedAt,
    int? unreadCount,
    String? title,
    bool? muted,
    bool? pinned,
  }) {
    return NativeConversation(
      id: c.id,
      kind: c.kind,
      title: title ?? c.title,
      unreadCount: unreadCount ?? c.unreadCount,
      preview: preview ?? c.preview,
      updatedAt: updatedAt ?? c.updatedAt,
      peerUserId: c.peerUserId,
      peerDisplayName: c.peerDisplayName,
      peerEnabled: c.peerEnabled,
      memberCount: c.memberCount,
      muted: muted ?? c.muted,
      pinned: pinned ?? c.pinned,
      businessType: c.businessType,
      peerDepartment: c.peerDepartment,
      peerRoleLabel: c.peerRoleLabel,
      peerAvatarPreset: c.peerAvatarPreset,
      peerAvatarObjectKey: c.peerAvatarObjectKey,
      peerAvatarUrl: c.peerAvatarUrl,
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
