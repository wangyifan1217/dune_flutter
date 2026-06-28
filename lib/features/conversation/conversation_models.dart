class NativeConversation {
  const NativeConversation({
    required this.id,
    required this.kind,
    required this.title,
    required this.unreadCount,
    required this.preview,
    required this.updatedAt,
    this.peerUserId,
    this.peerDisplayName,
    this.memberCount = 0,
    this.muted = false,
    this.pinned = false,
    this.businessType,
    this.peerDepartment,
    this.peerRoleLabel,
    this.peerAvatarPreset,
    this.peerAvatarObjectKey,
    this.dissolved = false,
    this.membershipStatus,
    this.assistantGenerating = false,
    this.assistantGeneratingStatus = '',
  });

  final int id;
  final String kind;
  final String title;
  final int unreadCount;
  final String preview;
  final DateTime? updatedAt;
  final int? peerUserId;
  final String? peerDisplayName;
  final int memberCount;
  final bool muted;
  final bool pinned;
  final String? businessType;
  final String? peerDepartment;
  final String? peerRoleLabel;
  final String? peerAvatarPreset;
  final String? peerAvatarObjectKey;
  final bool dissolved;
  final String? membershipStatus;
  final bool assistantGenerating;
  final String assistantGeneratingStatus;

  bool get isPrivate => kind == 'PRIVATE';
  bool get isAiAssistant => kind == 'AI_ASSISTANT';
  bool get isBroadcast => kind == 'BROADCAST';
  bool get isWorkgroupApproval => kind == 'WORKGROUP_APPROVAL';
  bool get isGroup => kind == 'WORKGROUP' || kind == 'GROUP';

  /// 私聊展示名：优先对端姓名（与 WebView `applyPrivateHeader` 一致）。
  String get displayTitle {
    if (!isPrivate) return title;
    final peer = peerDisplayName?.trim();
    if (peer != null && peer.isNotEmpty) return peer;
    final t = title.trim();
    if (t.isNotEmpty && t != '私聊') return t;
    return '私聊';
  }

  bool get isVisible {
    if (id <= 0) return false;
    if (dissolved) return false;
    final st = (membershipStatus ?? '').toUpperCase();
    if (st == 'LEFT' ||
        st == 'LEAVE' ||
        st == 'LEAVED' ||
        st == 'REMOVED' ||
        st == 'EXITED' ||
        st == 'QUIT' ||
        st == 'QUITED' ||
        st == 'KICKED' ||
        st == 'KICK_OUT') {
      return false;
    }
    return true;
  }

  int get sortTimestamp => updatedAt?.millisecondsSinceEpoch ?? 0;
}

class NativeChatMessage {
  const NativeChatMessage({
    required this.id,
    required this.senderUserId,
    required this.senderName,
    required this.kind,
    required this.bodyText,
    required this.createdAt,
    this.payload,
    this.peerRead = false,
    this.senderAvatarPreset,
    this.senderAvatarObjectKey,
  });

  final int id;
  final int senderUserId;
  final String senderName;
  final String kind;
  final String bodyText;
  final DateTime? createdAt;
  final Map<String, dynamic>? payload;
  final bool peerRead;
  final String? senderAvatarPreset;
  final String? senderAvatarObjectKey;
}

class NativeMessagePage {
  const NativeMessagePage({
    required this.items,
    this.hasMore = false,
    this.hasNewer = false,
    this.peerLastReadMessageId,
  });

  final List<NativeChatMessage> items;
  final bool hasMore;
  final bool hasNewer;
  final int? peerLastReadMessageId;
}

class NativeSearchMessagePage {
  const NativeSearchMessagePage({required this.items, this.hasMore = false});

  final List<NativeChatMessage> items;
  final bool hasMore;
}

class NativeGroupMember {
  const NativeGroupMember({
    required this.userId,
    required this.displayName,
    this.role,
    this.roleLabel,
  });

  final int userId;
  final String displayName;
  final String? role;
  final String? roleLabel;

  bool get isOwner =>
      (role ?? '').toUpperCase() == 'OWNER' || (roleLabel ?? '').contains('主');
}

class NativeGroupInfo {
  const NativeGroupInfo({
    required this.id,
    required this.kind,
    required this.title,
    this.members = const <NativeGroupMember>[],
    this.muted = false,
    this.pinned = false,
    this.isOwner = false,
    this.canLeave = false,
    this.dissolved = false,
    this.createdAt,
    this.businessType,
    this.businessId,
  });

  final int id;
  final String kind;
  final String title;
  final List<NativeGroupMember> members;
  final bool muted;
  final bool pinned;
  final bool isOwner;
  final bool canLeave;
  final bool dissolved;
  final DateTime? createdAt;
  final String? businessType;
  final String? businessId;

  bool get hasLinkedApproval {
    final bt = (businessType ?? '').trim();
    final bid = (businessId ?? '').trim();
    return bt.isNotEmpty && bid.isNotEmpty;
  }

  String get kindLabel {
    if (kind == 'WORKGROUP_APPROVAL') return '审批工作群';
    if (kind == 'WORKGROUP') return '工作群';
    return '群聊';
  }
}

class NovaHistoryTurn {
  const NovaHistoryTurn({
    required this.conversationId,
    required this.messageId,
    required this.title,
    required this.preview,
    required this.lastMessageAt,
  });

  final int conversationId;
  final int messageId;
  final String title;
  final String preview;
  final DateTime? lastMessageAt;
}

class UploadedAttachment {
  const UploadedAttachment({required this.url, required this.objectKey});

  final String url;
  final String objectKey;

  String get bestUrl => url.isNotEmpty ? url : objectKey;
}
