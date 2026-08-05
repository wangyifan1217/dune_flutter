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
    this.peerAvatarUrl,
    this.avatarMembers = const <ConversationAvatarMember>[],
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
  final String? peerAvatarUrl;
  final List<ConversationAvatarMember> avatarMembers;
  final bool dissolved;
  final String? membershipStatus;
  final bool assistantGenerating;
  final String assistantGeneratingStatus;

  bool get isPrivate => kind == 'PRIVATE';
  bool get isAiAssistant => kind == 'AI_ASSISTANT';
  bool get isBroadcast => kind == 'BROADCAST';
  bool get isWorkgroupApproval => kind == 'WORKGROUP_APPROVAL';
  bool get isGroup => kind == 'WORKGROUP' || kind == 'GROUP';
  bool get isRobot => kind == 'ROBOT';
  bool get isApprovalAssistant => kind == 'APPROVAL_ASSISTANT';
  bool get isTaskAssistant => kind == 'TASK_ASSISTANT';
  bool get isDriveAssistant => kind == 'DRIVE_ASSISTANT';
  bool get isReconciliationAssistant {
    final normalized = kind.trim().toUpperCase();
    return normalized == 'RECONCILIATION_ASSISTANT' ||
        normalized == 'RECONCILIATION' ||
        normalized == 'RECON_ASSISTANT' ||
        normalized == 'RECONCILIATION_BOT' ||
        normalized == 'RECON_BOT';
  }

  /// kind=ROBOT 时 businessType 存 robotKey。
  String? get robotKey {
    if (!isRobot) return null;
    final k = businessType?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

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

class ConversationAvatarMember {
  const ConversationAvatarMember({
    required this.userId,
    required this.displayName,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarUrl,
  });

  final int userId;
  final String displayName;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? avatarUrl;
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

  NativeChatMessage copyWith({
    String? senderAvatarPreset,
    String? senderAvatarObjectKey,
  }) {
    return NativeChatMessage(
      id: id,
      senderUserId: senderUserId,
      senderName: senderName,
      kind: kind,
      bodyText: bodyText,
      createdAt: createdAt,
      payload: payload,
      peerRead: peerRead,
      senderAvatarPreset: senderAvatarPreset ?? this.senderAvatarPreset,
      senderAvatarObjectKey:
          senderAvatarObjectKey ?? this.senderAvatarObjectKey,
    );
  }
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

/// IM 消息收藏（企微式：内容 + 来源人/群 + 收藏日期）。
class NativeMessageFavorite {
  const NativeMessageFavorite({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.conversationKind,
    required this.conversationTitle,
    required this.kind,
    required this.bodyText,
    required this.previewText,
    required this.senderName,
    this.senderUserId,
    this.payload,
    this.favoritedAt,
    this.messageCreatedAt,
  });

  final int id;
  final int conversationId;
  final int messageId;
  final String conversationKind;
  final String conversationTitle;
  final String kind;
  final String bodyText;
  final String previewText;
  final String senderName;
  final int? senderUserId;
  final Map<String, dynamic>? payload;
  final DateTime? favoritedAt;
  final DateTime? messageCreatedAt;

  bool get isPrivate => conversationKind.toUpperCase() == 'PRIVATE';
  bool get isGroup {
    final k = conversationKind.toUpperCase();
    return k == 'WORKGROUP' || k == 'GROUP' || k == 'WORKGROUP_APPROVAL';
  }

  /// 列表副标题：来自某某 / 某某群。
  String get sourceLabel {
    final title = conversationTitle.trim();
    if (title.isEmpty) return isGroup ? '来自群聊' : '来自会话';
    return '来自$title';
  }
}

class NativeMessageFavoritePage {
  const NativeMessageFavoritePage({required this.items, this.hasMore = false});

  final List<NativeMessageFavorite> items;
  final bool hasMore;
}

/// 会话内消息置顶（企微式：全员可见，最多 5 条）。
class NativePinnedMessage {
  const NativePinnedMessage({
    required this.id,
    required this.conversationId,
    required this.messageId,
    required this.kind,
    required this.bodyText,
    required this.previewText,
    required this.senderName,
    this.senderUserId,
    this.pinnedByUserId,
    this.pinnedByDisplayName = '',
    this.payload,
    this.pinnedAt,
    this.messageCreatedAt,
  });

  final int id;
  final int conversationId;
  final int messageId;
  final String kind;
  final String bodyText;
  final String previewText;
  final String senderName;
  final int? senderUserId;
  final int? pinnedByUserId;
  final String pinnedByDisplayName;
  final Map<String, dynamic>? payload;
  final DateTime? pinnedAt;
  final DateTime? messageCreatedAt;

  String get contentLabel {
    final text = pinnedContentSummary;
    final sender = senderName.trim();
    if (sender.isEmpty) return text;
    return '$sender：$text';
  }

  String get pinnedActionLabel {
    final operator = pinnedByDisplayName.trim();
    return '${operator.isEmpty ? '有人' : operator}置顶了';
  }

  /// 置顶条内容摘要：用消息本体，不用推送口吻（「发送了一张图片」等）。
  String get pinnedContentSummary {
    final upper = kind.trim().toUpperCase();
    final body = bodyText.trim();
    final fileName = _payloadFileName;

    switch (upper) {
      case 'IMAGE':
        return '[图片]';
      case 'VIDEO':
        return '[视频]';
      case 'AUDIO':
      case 'VOICE':
        return '[语音]';
      case 'FILE':
        final name = fileName.isNotEmpty
            ? fileName
            : _stripAttachmentPrefix(body);
        return name.isEmpty ? '[文件]' : '[文件] $name';
      case 'LINK':
        return body.isNotEmpty ? body : '[链接]';
    }

    if (_isPushStylePreview(previewText) || _isPushStylePreview(body)) {
      if (_looksLikeImageName(body) || _looksLikeImageName(fileName)) {
        return '[图片]';
      }
      if (_looksLikeVideoName(body) || body.startsWith('[视频]')) {
        return '[视频]';
      }
      if (body.startsWith('[语音]')) return '[语音]';
      if (body.startsWith('[文件]') || fileName.isNotEmpty) {
        final name = fileName.isNotEmpty
            ? fileName
            : _stripAttachmentPrefix(body);
        return name.isEmpty ? '[文件]' : '[文件] $name';
      }
    }

    final preview = previewText.trim();
    if (preview.isNotEmpty && !_isPushStylePreview(preview)) return preview;
    if (body.isNotEmpty) return body;
    return '[消息]';
  }

  String get _payloadFileName {
    final raw = payload?['fileName'] ?? payload?['name'];
    return '${raw ?? ''}'.trim();
  }

  static bool _isPushStylePreview(String text) {
    final t = text.trim();
    return t == '发送了一张图片' ||
        t == '发送了一个文件' ||
        t == '发送了一个视频' ||
        t == '发送了一条语音' ||
        t == '您有新消息' ||
        t == '[新消息]';
  }

  static String _stripAttachmentPrefix(String text) {
    final t = text.trim();
    final idx = t.indexOf(']');
    if (t.startsWith('[') && idx > 0 && idx + 1 < t.length) {
      return t.substring(idx + 1).trim();
    }
    return t;
  }

  static bool _looksLikeImageName(String text) {
    return RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|heic|heif)$',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  static bool _looksLikeVideoName(String text) {
    return RegExp(
      r'\.(mp4|mov|m4v|webm|mkv|avi)$',
      caseSensitive: false,
    ).hasMatch(text.trim());
  }

  /// 兼容其它使用方的单行摘要。
  String get barLabel => '$pinnedActionLabel  $contentLabel';
}

class NativeGroupMember {
  const NativeGroupMember({
    required this.userId,
    required this.displayName,
    this.role,
    this.roleLabel,
    this.department,
    this.title,
    this.avatarPreset,
    this.avatarObjectKey,
  });

  final int userId;
  final String displayName;
  final String? role;
  final String? roleLabel;
  final String? department;
  final String? title;
  final String? avatarPreset;
  final String? avatarObjectKey;

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
