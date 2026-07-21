import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import 'conversation_models.dart';
import 'conversation_service.dart';

/// 底部弹窗选择私聊/群聊会话，返回会话 ID；取消返回 null。
Future<int?> showConversationPickerSheet({
  required BuildContext context,
  required ConversationService service,
  String title = '选择会话',
  int? highlightConversationId,
}) async {
  final result = await showConversationMultiPickerSheet(
    context: context,
    service: service,
    title: title,
    multiSelect: false,
    highlightConversationId: highlightConversationId,
  );
  if (result == null || result.isEmpty) return null;
  return result.first;
}

/// 多选会话（UI 与会议纪要「转发至」一致：搜索 + 头像 + 标题/预览）。
/// 取消返回 null；确认返回选中 ID 集合（可为 empty 若未选）。
Future<Set<int>?> showConversationMultiPickerSheet({
  required BuildContext context,
  required ConversationService service,
  String title = '选择聊天',
  bool multiSelect = true,
  Set<int>? initialSelected,
  int maxCount = 20,
  int? highlightConversationId,
}) async {
  List<NativeConversation> rows;
  try {
    rows = await service.fetchConversations();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('会话列表加载失败：${friendlyErrorText(e)}')),
      );
    }
    return null;
  }
  if (!context.mounted) return null;

  const allowedKinds = <String>{
    'PRIVATE',
    'GROUP',
    'WORKGROUP',
    'WORKGROUP_APPROVAL',
  };
  final candidates = rows
      .where(
        (c) =>
            c.isVisible &&
            c.id > 0 &&
            allowedKinds.contains(c.kind.toUpperCase()),
      )
      .toList(growable: false);
  final searchController = TextEditingController();
  var keyword = '';
  final selected = <int>{...?initialSelected};

  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final q = keyword.trim().toLowerCase();
          final filtered = q.isEmpty
              ? candidates
              : candidates
                    .where((c) {
                      final t = c.displayTitle.toLowerCase();
                      final p = c.preview.toLowerCase();
                      return t.contains(q) || p.contains(q);
                    })
                    .toList(growable: false);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (multiSelect)
                        TextButton(
                          onPressed: () =>
                              Navigator.of(context).pop(Set<int>.from(selected)),
                          style: TextButton.styleFrom(
                            foregroundColor: DunesColors.brandPurple,
                          ),
                          child: Text('完成(${selected.length})'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setModalState(() => keyword = value);
                    },
                    decoration: InputDecoration(
                      hintText: '搜索',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: DunesColors.bgSoft,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            '暂无可选会话',
                            style: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            color: DunesColors.borderSoft,
                          ),
                          itemBuilder: (context, index) {
                            final c = filtered[index];
                            final subtitle = c.preview.trim();
                            final checked = selected.contains(c.id);
                            return ListTile(
                              selected: multiSelect && checked,
                              selectedTileColor: DunesColors.brandPurpleSoft,
                              leading: _ConversationPickerAvatar(
                                conversation: c,
                                service: service,
                              ),
                              title: Text(
                                c.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: subtitle.isEmpty
                                  ? null
                                  : Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: multiSelect
                                  ? Icon(
                                      checked
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 22,
                                      color: checked
                                          ? DunesColors.brandPurple
                                          : DunesColors.text3,
                                    )
                                  : (highlightConversationId != null &&
                                            c.id == highlightConversationId
                                        ? const Text(
                                            '当前',
                                            style: TextStyle(
                                              color: DunesColors.text3,
                                            ),
                                          )
                                        : null),
                              onTap: () {
                                if (!multiSelect) {
                                  Navigator.of(context).pop(<int>{c.id});
                                  return;
                                }
                                setModalState(() {
                                  if (checked) {
                                    selected.remove(c.id);
                                  } else {
                                    if (selected.length >= maxCount) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('最多选择 $maxCount 个会话'),
                                        ),
                                      );
                                      return;
                                    }
                                    selected.add(c.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  ).whenComplete(searchController.dispose);
}

class _ConversationPickerAvatar extends StatelessWidget {
  const _ConversationPickerAvatar({
    required this.conversation,
    required this.service,
  });

  final NativeConversation conversation;
  final ConversationService service;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    const size = 36.0;
    const radius = size * 0.18;
    if (!c.isPrivate) {
      if (c.avatarMembers.isNotEmpty) {
        return GroupCompositeAvatar(
          members: c.avatarMembers,
          size: size,
          avatarService: service,
        );
      }
      if (c.isWorkgroupApproval) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              colors: [Color(0xFF9079C2), Color(0xFF6A4FA0)],
            ),
          ),
          child: Icon(
            Icons.assignment_outlined,
            color: Colors.white,
            size: size * 0.39,
          ),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            colors: [Color(0xFFCABCEB), Color(0xFFA88CD8)],
          ),
        ),
        child: Icon(
          Icons.groups_outlined,
          color: Colors.white,
          size: size * 0.39,
        ),
      );
    }
    final initial = c.displayTitle.trim().isNotEmpty
        ? c.displayTitle.trim().substring(0, 1)
        : '?';
    return ImUserAvatar(
      initial: initial,
      seed: c.peerUserId ?? c.id,
      size: size,
      avatarPreset: c.peerAvatarPreset,
      avatarObjectKey: c.peerAvatarObjectKey,
      avatarUrl: c.peerAvatarUrl,
      avatarService: service,
      borderRadius: radius,
    );
  }
}
