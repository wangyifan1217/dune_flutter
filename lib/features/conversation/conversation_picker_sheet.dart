import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import 'conversation_models.dart';
import 'conversation_service.dart';

/// 底部弹窗选择私聊/群聊会话，返回会话 ID；取消返回 null。
///
/// 默认列出已有会话；搜索时可命中尚未建会话的联系人，选中后会先
/// [ConversationService.ensurePrivateConversationForPeer] 再建/复用私聊。
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
    'SELF_MEMO',
    'GROUP',
    'WORKGROUP',
    'WORKGROUP_APPROVAL',
  };
  final candidates = rows
      .where(
        (c) =>
            c.isListedInInbox &&
            c.id > 0 &&
            allowedKinds.contains(c.kind.toUpperCase()),
      )
      .toList(growable: false);

  return showModalBottomSheet<Set<int>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ConversationPickerBody(
      service: service,
      title: title,
      candidates: candidates,
      multiSelect: multiSelect,
      maxCount: maxCount,
      highlightConversationId: highlightConversationId,
      initialSelected: initialSelected,
    ),
  );
}

class _ConversationPickerBody extends StatefulWidget {
  const _ConversationPickerBody({
    required this.service,
    required this.title,
    required this.candidates,
    required this.multiSelect,
    required this.maxCount,
    this.highlightConversationId,
    this.initialSelected,
  });

  final ConversationService service;
  final String title;
  final List<NativeConversation> candidates;
  final bool multiSelect;
  final int maxCount;
  final int? highlightConversationId;
  final Set<int>? initialSelected;

  @override
  State<_ConversationPickerBody> createState() =>
      _ConversationPickerBodyState();
}

class _ConversationPickerBodyState extends State<_ConversationPickerBody> {
  final TextEditingController _searchController = TextEditingController();
  late final ContactService _contactService = ContactService(
    session: widget.service.session,
  );

  String _keyword = '';
  List<NativeContact> _contactHits = const <NativeContact>[];
  bool _contactSearching = false;
  int _contactSearchSeq = 0;
  Timer? _searchDebounce;
  late final Set<int> _selected = <int>{...?widget.initialSelected};
  bool _resolvingContact = false;

  Set<int> get _existingPrivatePeers {
    final peers = <int>{};
    for (final c in widget.candidates) {
      if (!c.isPrivate || c.isSelfMemo) continue;
      final peer = c.peerUserId;
      if (peer != null && peer > 0) peers.add(peer);
    }
    return peers;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final raw = value.trim();
    setState(() {
      _keyword = raw;
      if (raw.isEmpty) {
        _contactHits = const <NativeContact>[];
        _contactSearching = false;
      }
    });
    if (raw.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      unawaited(_searchContacts(raw));
    });
  }

  Future<void> _searchContacts(String keyword) async {
    final seq = ++_contactSearchSeq;
    if (mounted) setState(() => _contactSearching = true);
    try {
      final org = await _contactService.fetchOrgContacts(keyword: keyword);
      final external = await _contactService.fetchExternalContacts(
        keyword: keyword,
      );
      if (!mounted || seq != _contactSearchSeq) return;

      final existingPeers = _existingPrivatePeers;
      final selfId = widget.service.session.userId;
      final seen = <int>{};
      final hits = <NativeContact>[];
      for (final c in [...org.searchItems, ...external]) {
        if (c.userId <= 0 || c.userId == selfId) continue;
        if (!c.enabled) continue;
        if (existingPeers.contains(c.userId)) continue;
        if (!seen.add(c.userId)) continue;
        hits.add(c);
      }
      setState(() {
        _contactHits = hits;
        _contactSearching = false;
      });
    } catch (_) {
      if (!mounted || seq != _contactSearchSeq) return;
      setState(() {
        _contactHits = const <NativeContact>[];
        _contactSearching = false;
      });
    }
  }

  Future<void> _pickContact(NativeContact contact) async {
    if (_resolvingContact) return;
    setState(() => _resolvingContact = true);
    try {
      final conversationId = await widget.service
          .ensurePrivateConversationForPeer(contact.userId);
      if (!mounted) return;
      if (conversationId == null || conversationId <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法创建私聊会话')));
        return;
      }
      if (!widget.multiSelect) {
        Navigator.of(context).pop(<int>{conversationId});
        return;
      }
      setState(() {
        if (_selected.contains(conversationId)) {
          _selected.remove(conversationId);
        } else if (_selected.length >= widget.maxCount) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('最多选择 ${widget.maxCount} 个会话')),
          );
        } else {
          _selected.add(conversationId);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开私聊失败：${friendlyErrorText(e)}')),
      );
    } finally {
      if (mounted) setState(() => _resolvingContact = false);
    }
  }

  List<NativeConversation> get _filteredConversations {
    final q = _keyword.trim().toLowerCase();
    if (q.isEmpty) return widget.candidates;
    return widget.candidates
        .where((c) {
          final t = c.displayTitle.toLowerCase();
          final p = c.preview.toLowerCase();
          return t.contains(q) || p.contains(q);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConversations;
    final showContacts = _keyword.trim().isNotEmpty;
    final hasContactBlock =
        showContacts && (_contactSearching || _contactHits.isNotEmpty);
    final empty =
        filtered.isEmpty &&
        !_contactSearching &&
        _contactHits.isEmpty &&
        !_resolvingContact;

    return SafeArea(
      child: Stack(
        children: [
          ConstrainedBox(
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
                          widget.title,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.multiSelect)
                        TextButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(Set<int>.from(_selected)),
                          style: TextButton.styleFrom(
                            foregroundColor: DunesColors.brandPurple,
                          ),
                          child: Text('完成(${_selected.length})'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '搜索会话或联系人',
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
                  child: empty
                      ? Center(
                          child: Text(
                            showContacts ? '无匹配的会话或联系人' : '暂无可选会话',
                            style: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            if (filtered.isNotEmpty) ...[
                              if (showContacts)
                                const _PickerSectionHeader(label: '会话'),
                              ...List.generate(filtered.length, (index) {
                                final c = filtered[index];
                                return Column(
                                  children: [
                                    _conversationTile(c),
                                    if (index != filtered.length - 1 ||
                                        hasContactBlock)
                                      const Divider(
                                        height: 1,
                                        color: DunesColors.borderSoft,
                                      ),
                                  ],
                                );
                              }),
                            ],
                            if (hasContactBlock) ...[
                              const _PickerSectionHeader(label: '联系人'),
                              if (_contactSearching && _contactHits.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    '正在搜索联系人…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: DunesColors.text3,
                                    ),
                                  ),
                                )
                              else
                                ...List.generate(_contactHits.length, (index) {
                                  final contact = _contactHits[index];
                                  return Column(
                                    children: [
                                      _contactTile(contact),
                                      if (index != _contactHits.length - 1)
                                        const Divider(
                                          height: 1,
                                          color: DunesColors.borderSoft,
                                        ),
                                    ],
                                  );
                                }),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (_resolvingContact)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _conversationTile(NativeConversation c) {
    final subtitle = c.preview.trim();
    final checked = _selected.contains(c.id);
    return ListTile(
      selected: widget.multiSelect && checked,
      selectedTileColor: DunesColors.brandPurpleSoft,
      leading: _ConversationPickerAvatar(
        conversation: c,
        service: widget.service,
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
      trailing: widget.multiSelect
          ? Icon(
              checked ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 22,
              color: checked ? DunesColors.brandPurple : DunesColors.text3,
            )
          : (widget.highlightConversationId != null &&
                    c.id == widget.highlightConversationId
                ? const Text(
                    '当前',
                    style: TextStyle(color: DunesColors.text3),
                  )
                : null),
      onTap: () {
        if (!widget.multiSelect) {
          Navigator.of(context).pop(<int>{c.id});
          return;
        }
        setState(() {
          if (checked) {
            _selected.remove(c.id);
          } else {
            if (_selected.length >= widget.maxCount) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('最多选择 ${widget.maxCount} 个会话')),
              );
              return;
            }
            _selected.add(c.id);
          }
        });
      },
    );
  }

  Widget _contactTile(NativeContact contact) {
    final dept = (contact.department ?? '').trim();
    final role = contact.primaryRole;
    final previewParts = <String>[
      if (dept.isNotEmpty) dept,
      if (role.isNotEmpty) role,
    ];
    final preview = previewParts.isEmpty ? '点击发起会话' : previewParts.join(' · ');
    final initial = contact.displayLabel.isNotEmpty
        ? contact.displayLabel.substring(0, 1)
        : '?';
    return ListTile(
      leading: ImUserAvatar(
        initial: initial,
        seed: contact.userId,
        size: 36,
        avatarPreset: contact.avatarPreset,
        avatarObjectKey: contact.avatarObjectKey,
        avatarService: widget.service,
        borderRadius: 36 * 0.18,
      ),
      title: Text(
        contact.displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Text(
        '联系人',
        style: TextStyle(fontSize: 12, color: DunesColors.text3),
      ),
      onTap: () => unawaited(_pickContact(contact)),
    );
  }
}

class _PickerSectionHeader extends StatelessWidget {
  const _PickerSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DunesColors.text3,
        ),
      ),
    );
  }
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
