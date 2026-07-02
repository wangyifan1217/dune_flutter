import 'package:flutter/material.dart';

import '../../core/widgets/cached_network_image.dart';
import 'conversation_models.dart';

/// 会话头像签名，用于判断静默刷新时是否可保留本地已解析头像。
String conversationAvatarSignature(NativeConversation c) {
  if (c.isPrivate) {
    return avatarSourceSignature(
      preset: c.peerAvatarPreset ?? '',
      objectKey: c.peerAvatarObjectKey ?? '',
      directUrl: c.peerAvatarUrl ?? '',
    );
  }
  if (c.avatarMembers.isEmpty) return '';
  return c.avatarMembers
      .map(
        (m) => avatarSourceSignature(
          preset: m.avatarPreset ?? '',
          objectKey: m.avatarObjectKey ?? '',
          directUrl: m.avatarUrl ?? '',
        ),
      )
      .join('|');
}

/// 静默拉取列表时合并：预览/未读等用服务端，头像未变则保留旧引用，减少重建闪烁。
/// [selfAvatar] 不为空时，群拼贴里当前用户头像始终用最新资料，避免 merge 留住旧图。
List<NativeConversation> mergeInboxConversations(
  List<NativeConversation> current,
  List<NativeConversation> fetched, {
  UserAvatarSnapshot? selfAvatar,
}) {
  if (current.isEmpty) {
    return applySelfAvatarToConversations(fetched, selfAvatar);
  }
  final prevById = {for (final c in current) c.id: c};
  final merged = fetched
      .map((server) {
        final prev = prevById[server.id];
        if (prev == null) return server;
        if (conversationAvatarSignature(prev) ==
            conversationAvatarSignature(server)) {
          return _mergeKeepingAvatars(prev, server, selfAvatar: selfAvatar);
        }
        return server;
      })
      .toList(growable: false);
  return applySelfAvatarToConversations(merged, selfAvatar);
}

List<NativeConversation> applySelfAvatarToConversations(
  List<NativeConversation> rows,
  UserAvatarSnapshot? selfAvatar,
) {
  if (selfAvatar == null || selfAvatar.userId <= 0) return rows;
  return rows
      .map((c) => applySelfAvatarToConversation(c, selfAvatar))
      .toList(growable: false);
}

NativeConversation applySelfAvatarToConversation(
  NativeConversation c,
  UserAvatarSnapshot selfAvatar,
) {
  if (c.avatarMembers.isEmpty) return c;
  var changed = false;
  final members = c.avatarMembers.map((m) {
    if (m.userId != selfAvatar.userId) return m;
    if (!_selfAvatarDiffers(m, selfAvatar)) return m;
    changed = true;
    return ConversationAvatarMember(
      userId: m.userId,
      displayName: m.displayName,
      avatarPreset: selfAvatar.avatarPreset.isNotEmpty
          ? selfAvatar.avatarPreset
          : m.avatarPreset,
      avatarObjectKey: selfAvatar.avatarObjectKey.isNotEmpty
          ? selfAvatar.avatarObjectKey
          : m.avatarObjectKey,
      avatarUrl: selfAvatar.avatarUrl.isNotEmpty
          ? selfAvatar.avatarUrl
          : m.avatarUrl,
    );
  }).toList(growable: false);
  if (!changed) return c;
  return NativeConversation(
    id: c.id,
    kind: c.kind,
    title: c.title,
    unreadCount: c.unreadCount,
    preview: c.preview,
    updatedAt: c.updatedAt,
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
    peerAvatarUrl: c.peerAvatarUrl,
    avatarMembers: members,
    dissolved: c.dissolved,
    membershipStatus: c.membershipStatus,
    assistantGenerating: c.assistantGenerating,
    assistantGeneratingStatus: c.assistantGeneratingStatus,
  );
}

bool _selfAvatarDiffers(
  ConversationAvatarMember member,
  UserAvatarSnapshot selfAvatar,
) {
  return avatarSourceSignature(
        preset: member.avatarPreset ?? '',
        objectKey: member.avatarObjectKey ?? '',
        directUrl: member.avatarUrl ?? '',
      ) !=
      selfAvatar.sourceSignature;
}

NativeConversation _mergeKeepingAvatars(
  NativeConversation prev,
  NativeConversation server, {
  UserAvatarSnapshot? selfAvatar,
}) {
  final merged = NativeConversation(
    id: server.id,
    kind: server.kind,
    title: server.title,
    unreadCount: server.unreadCount,
    preview: server.preview,
    updatedAt: server.updatedAt,
    peerUserId: server.peerUserId,
    peerDisplayName: server.peerDisplayName,
    memberCount: server.memberCount,
    muted: server.muted,
    pinned: server.pinned,
    businessType: server.businessType,
    peerDepartment: server.peerDepartment,
    peerRoleLabel: server.peerRoleLabel,
    peerAvatarPreset: prev.peerAvatarPreset,
    peerAvatarObjectKey: prev.peerAvatarObjectKey,
    peerAvatarUrl: prev.peerAvatarUrl,
    avatarMembers: prev.avatarMembers,
    dissolved: server.dissolved,
    membershipStatus: server.membershipStatus,
    assistantGenerating: server.assistantGenerating,
    assistantGeneratingStatus: server.assistantGeneratingStatus,
  );
  if (selfAvatar != null && selfAvatar.userId > 0) {
    return applySelfAvatarToConversation(merged, selfAvatar);
  }
  return merged;
}

void warmConversationAvatarCache(List<NativeConversation> rows) {
  for (final c in rows) {
    warmConversationAvatarUrls(
      peerAvatarObjectKey: c.peerAvatarObjectKey,
      peerAvatarUrl: c.peerAvatarUrl,
      members: c.avatarMembers.map(
        (m) => (objectKey: m.avatarObjectKey, url: m.avatarUrl),
      ),
    );
  }
}

/// 列表加载后预解码头像到 Flutter 图片缓存，滚动/刷新时更快出图。
Future<void> prefetchConversationAvatars(
  BuildContext context,
  List<NativeConversation> rows, {
  int limit = 48,
}) async {
  if (!context.mounted) return;
  var count = 0;
  for (final c in rows) {
    if (count >= limit) break;
    count += await _prefetchHttpAvatar(context, c.peerAvatarUrl);
    for (final m in c.avatarMembers) {
      if (count >= limit) break;
      count += await _prefetchHttpAvatar(context, m.avatarUrl);
    }
  }
}

Future<int> _prefetchHttpAvatar(BuildContext context, String? url) async {
  final raw = (url ?? '').trim();
  if (!raw.startsWith('http')) return 0;
  if (!context.mounted) return 0;
  try {
    await precacheImage(NetworkImage(raw), context);
    return 1;
  } catch (_) {
    return 0;
  }
}
