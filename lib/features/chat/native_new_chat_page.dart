import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'group_type_picker.dart';
import 'im_ui_kit.dart';
import 'user_avatar_widget.dart';

class NativeNewChatPage extends StatefulWidget {
  const NativeNewChatPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenPrivateChat,
    required this.onOpenGroupChat,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenPrivateChat;
  final ValueChanged<NativeConversation> onOpenGroupChat;

  @override
  State<NativeNewChatPage> createState() => _NativeNewChatPageState();
}

class _NativeNewChatPageState extends State<NativeNewChatPage> {
  late final ContactService _service;
  late final ConversationService _conversationService;
  late final ConversationRealtimeService _realtime;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  int _total = 0;
  List<NativeDepartment> _departments = const <NativeDepartment>[];
  List<NativeContact> _searchItems = const <NativeContact>[];
  List<NativeContact> _externalContacts = const <NativeContact>[];
  Set<int> _onlineUsers = <int>{};
  Set<int> _selectedUserIds = <int>{};

  /// 跨搜索保留已见过的联系人，避免已选成员头像/姓名退化成 userId。
  final Map<int, NativeContact> _knownContacts = <int, NativeContact>{};
  StreamSubscription<Set<int>>? _onlineSub;
  _NewChatMode _mode = _NewChatMode.group;

  @override
  void initState() {
    super.initState();
    _service = ContactService(session: widget.session);
    _conversationService = ConversationService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    _load();
    unawaited(_bootRealtime());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _onlineSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootRealtime() async {
    try {
      await _realtime.connect();
      _onlineSub = _realtime.trackOnlineUsers((ids) {
        if (!mounted) return;
        setState(() => _onlineUsers = ids);
      });
      unawaited(_realtime.refreshOnlinePresence());
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final searching = _searchController.text.trim().isNotEmpty;
      final data = await _service.fetchOrgContacts(
        keyword: _searchController.text,
      );
      final external = searching
          ? await _service.fetchExternalContacts(
              keyword: _searchController.text,
            )
          : await _service.fetchExternalContacts();
      if (!mounted) return;
      setState(() {
        _total = data.total;
        if (!searching) _departments = data.departments;
        final mergedSearch = [...data.searchItems, ...external]
            .where((c) => c.enabled && c.userId != widget.session.userId)
            .toList(growable: false);
        _searchItems = searching
            ? mergedSearch
            : data.searchItems
                  .where((c) => c.enabled && c.userId != widget.session.userId)
                  .toList(growable: false);
        _externalContacts = external
            .where((c) => c.enabled && c.userId != widget.session.userId)
            .toList(growable: false);
        _rememberContacts(data.searchItems);
        _rememberDepartments(data.departments);
        _rememberContacts(external);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _toggleMode(_NewChatMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      if (mode == _NewChatMode.private && _selectedUserIds.length > 1) {
        _selectedUserIds = <int>{_selectedUserIds.first};
      }
    });
  }

  void _toggleSelected(NativeContact contact) {
    if (!contact.enabled ||
        contact.userId <= 0 ||
        contact.userId == widget.session.userId) {
      return;
    }
    _rememberContacts([contact]);
    setState(() {
      final next = Set<int>.from(_selectedUserIds);
      if (_mode == _NewChatMode.private) {
        if (next.contains(contact.userId)) {
          next.clear();
        } else {
          next
            ..clear()
            ..add(contact.userId);
        }
      } else if (next.contains(contact.userId)) {
        next.remove(contact.userId);
      } else {
        next.add(contact.userId);
      }
      _selectedUserIds = next;
    });
  }

  void _selectAllMembers() {
    final contacts = _allSelectableContacts();
    _rememberContacts(contacts);
    setState(() {
      if (_mode == _NewChatMode.private) {
        _selectedUserIds = contacts.isEmpty
            ? <int>{}
            : <int>{contacts.first.userId};
      } else {
        _selectedUserIds = contacts
            .map((c) => c.userId)
            .where((id) => id > 0 && id != widget.session.userId)
            .toSet();
      }
    });
  }

  void _clearSelected() {
    setState(() => _selectedUserIds = <int>{});
  }

  List<NativeContact> _allSelectableContacts() {
    final all = <NativeContact>[];
    void walk(NativeDepartment dep) {
      all.addAll(
        dep.users.where((c) => c.enabled && c.userId != widget.session.userId),
      );
      for (final child in dep.children) {
        walk(child);
      }
    }

    for (final dep in _departments) {
      walk(dep);
    }
    final seen = <int>{};
    final deduped = all
        .where((c) => seen.add(c.userId))
        .toList(growable: false);
    if (deduped.isNotEmpty) return deduped;
    return _searchItems
        .where((c) => seen.add(c.userId))
        .toList(growable: false);
  }

  void _rememberContacts(Iterable<NativeContact> rows) {
    for (final c in rows) {
      if (c.userId > 0) _knownContacts[c.userId] = c;
    }
  }

  void _rememberDepartments(List<NativeDepartment> deps) {
    for (final d in deps) {
      _rememberContacts(d.users);
      _rememberDepartments(d.children);
    }
  }

  NativeContact? _contactById(int userId) {
    final cached = _knownContacts[userId];
    if (cached != null) return cached;
    for (final c in _searchItems) {
      if (c.userId == userId) {
        _rememberContacts([c]);
        return c;
      }
    }
    for (final c in _externalContacts) {
      if (c.userId == userId) {
        _rememberContacts([c]);
        return c;
      }
    }
    NativeContact? hit;
    void walk(NativeDepartment dep) {
      for (final c in dep.users) {
        if (c.userId == userId) {
          hit = c;
          return;
        }
      }
      for (final child in dep.children) {
        if (hit != null) return;
        walk(child);
      }
    }

    for (final dep in _departments) {
      if (hit != null) break;
      walk(dep);
    }
    if (hit != null) _rememberContacts([hit!]);
    return hit;
  }

  Future<void> _createConversation() async {
    if (_creating) return;
    final ids = _selectedUserIds
        .where((id) => id > 0 && id != widget.session.userId)
        .toList(growable: false);
    if (ids.isEmpty) {
      showDunesSoonToast(context, '请至少选择一位同事');
      return;
    }
    final creatingGroup = _mode != _NewChatMode.private && ids.length >= 2;
    NewGroupType? groupType;
    if (creatingGroup) {
      final previewNames = ids
          .take(3)
          .map((id) => _contactById(id)?.displayName ?? '成员')
          .join('、');
      final more = ids.length > 3 ? ' 等' : '';
      groupType = await showCreateGroupTypeDialog(
        context,
        membersText: '将与 $previewNames$more共 ${ids.length} 人创建群聊，是否继续？',
      );
      if (groupType == null || !mounted) return;
    }
    setState(() => _creating = true);
    try {
      if (_mode == _NewChatMode.private || ids.length == 1) {
        final peerId = ids.first;
        if (!mounted) return;
        // 不预先创建服务端会话：首次发消息再建。
        widget.onOpenPrivateChat(peerId);
        return;
      }
      final title = ids
          .take(3)
          .map((id) => _contactById(id)?.displayName ?? '成员')
          .join('、');
      final conversation = await _conversationService.createConversation(
        kind: (groupType ?? NewGroupType.normal).kind,
        memberUserIds: ids,
        title: title.isEmpty ? '群聊' : title,
        replySla: (groupType ?? NewGroupType.normal).replySla,
      );
      if (!mounted) return;
      if (conversation == null) throw Exception('创建群聊失败');
      widget.onOpenGroupChat(conversation);
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '创建会话失败：${friendlyErrorText(e)}',
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    return Scaffold(
      backgroundColor: ImVisualTokens.groupedBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: ImVisualTokens.cardSurface(context),
              child: Column(
                children: [
                  _NewChatHeader(
                    onBack: widget.onBack,
                    creating: _creating,
                    onCreate: _createConversation,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _NewChatModeGrid(mode: _mode, onPick: _toggleMode),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: ImVisualTokens.groupedBackground(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: ImVisualTokens.hairlineBorder(context),
                          width: 0.7,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              cursorColor: accent,
                              onChanged: _onSearchChanged,
                              onSubmitted: (_) => _load(),
                              style: DunesTypography.sans(
                                fontSize: 13.5,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text,
                                ),
                                context: context,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: '搜索同事 · 部门 · 角色',
                                hintStyle: DunesTypography.sans(
                                  fontSize: 13.5,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.text3,
                                  ),
                                  context: context,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _NewChatSelectedStack(
              selectedUserIds: _selectedUserIds.toList()..sort(),
              resolveContact: _contactById,
              onRemove: (userId) =>
                  setState(() => _selectedUserIds.remove(userId)),
            ),
            _NewChatBulkBar(
              onSelectAll: _selectAllMembers,
              onClearAll: _clearSelected,
              privateMode: _mode == _NewChatMode.private,
            ),
            _NewChatOrgLabel(total: _total),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                        ),
                      ),
                    )
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final searching = _searchController.text.trim().isNotEmpty;
    if (searching) {
      if (_searchItems.isEmpty) {
        return Center(
          child: Text(
            '无匹配联系人',
            style: TextStyle(
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: _searchItems
            .map(
              (c) => _NewChatPickRow(
                contact: c,
                selected: _selectedUserIds.contains(c.userId),
                online: _onlineUsers.contains(c.userId),
                avatarService: _conversationService,
                onTap: () => _toggleSelected(c),
              ),
            )
            .toList(growable: false),
      );
    }
    if (_departments.isEmpty && _externalContacts.isEmpty) {
      return Center(
        child: Text(
          '暂无组织数据',
          style: TextStyle(
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ..._departments
            .map(
              (dep) => _NewChatDeptBlock(
                key: ValueKey('dept-${dep.id}'),
                department: dep,
                currentUserId: widget.session.userId,
                selectedUserIds: _selectedUserIds,
                onlineUsers: _onlineUsers,
                avatarService: _conversationService,
                onToggleContact: _toggleSelected,
              ),
            )
            .toList(growable: false),
        if (_externalContacts.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Text(
                  '外部用户',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.accent),
                  ),
                ),
              ],
            ),
          ),
          ..._externalContacts
              .map(
                (c) => _NewChatPickRow(
                  contact: c,
                  selected: _selectedUserIds.contains(c.userId),
                  online: _onlineUsers.contains(c.userId),
                  avatarService: _conversationService,
                  onTap: () => _toggleSelected(c),
                ),
              )
              .toList(growable: false),
        ],
      ],
    );
  }
}

class _NewChatOrgLabel extends StatelessWidget {
  const _NewChatOrgLabel({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ImVisualTokens.accentSoftSurface(context),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'HeUnion',
              style: DunesTypography.sans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ImVisualTokens.accentText(context),
                context: context,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              height: 0.5,
              color: ImVisualTokens.hairlineBorder(context),
            ),
          ),
          Text(
            '$total 人',
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
        ],
      ),
    );
  }
}

enum _NewChatMode { group, private }

class _NewChatHeader extends StatelessWidget {
  const _NewChatHeader({
    required this.onBack,
    required this.creating,
    required this.onCreate,
  });

  final VoidCallback onBack;
  final bool creating;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '新建会话',
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
                Text(
                  '选择成员 · 单聊 / 群聊',
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    color: DunesColors.resolve(context, DunesColors.text3),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
          ImTapScale(
            borderRadius: BorderRadius.circular(12),
            onTap: creating ? null : onCreate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: creating ? null : ImVisualTokens.primaryGradient(context),
                color: creating ? accent.withValues(alpha: 0.45) : null,
                borderRadius: BorderRadius.circular(12),
                boxShadow: creating
                    ? const []
                    : [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.24),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Text(
                creating ? '创建中' : '创建',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatModeGrid extends StatelessWidget {
  const _NewChatModeGrid({required this.mode, required this.onPick});

  final _NewChatMode mode;
  final ValueChanged<_NewChatMode> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      childAspectRatio: 2.55,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _NewChatModeCard(
          title: '创建群聊',
          subtitle: '3+ 成员',
          icon: Icons.groups_outlined,
          selected: mode == _NewChatMode.group,
          onTap: () => onPick(_NewChatMode.group),
        ),
        _NewChatModeCard(
          title: '单聊',
          subtitle: '1 对 1 私聊',
          icon: Icons.person_outline,
          selected: mode == _NewChatMode.private,
          onTap: () => onPick(_NewChatMode.private),
        ),
      ],
    );
  }
}

class _NewChatModeCard extends StatelessWidget {
  const _NewChatModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    return ImTapScale(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: ImVisualTokens.fastAnim,
        curve: ImVisualTokens.iosCurve,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? ImVisualTokens.accentSoftSurface(context)
              : ImVisualTokens.cardSurface(context),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.48)
                : ImVisualTokens.hairlineBorder(context),
            width: selected ? 1.2 : 0.8,
          ),
          boxShadow: selected ? const [] : ImVisualTokens.softCardShadow(context),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: selected ? ImVisualTokens.primaryGradient(context) : null,
                color: selected
                    ? null
                    : ImVisualTokens.groupedBackground(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 17,
                color: selected
                    ? Colors.white
                    : DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? ImVisualTokens.accentText(context)
                          : DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChatSelectedStack extends StatelessWidget {
  const _NewChatSelectedStack({
    required this.selectedUserIds,
    required this.resolveContact,
    required this.onRemove,
  });

  final List<int> selectedUserIds;
  final NativeContact? Function(int userId) resolveContact;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          DunesColors.bgSoft,
          role: DunesColorRole.surface,
        ),
        border: Border(
          bottom: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '已选 ${selectedUserIds.length}：',
            style: DunesTypography.mono(
              fontSize: 9,
              color: DunesColors.resolve(context, DunesColors.text3),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04 * 9,
              context: context,
            ),
          ),
          if (selectedUserIds.isEmpty)
            Text(
              '请从 HeUnion 选择成员',
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            )
          else
            ...selectedUserIds.map((id) {
              final name = resolveContact(id)?.displayName ?? '成员$id';
              return InkWell(
                onTap: () => onRemove(id),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      DunesColors.accent,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.resolve(context, Colors.white),
                          fontWeight: FontWeight.w600,
                          context: context,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: DunesColors.resolve(context, Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _NewChatBulkBar extends StatelessWidget {
  const _NewChatBulkBar({
    required this.onSelectAll,
    required this.onClearAll,
    required this.privateMode,
  });

  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  final bool privateMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 6),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: privateMode ? null : onSelectAll,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: DunesColors.resolve(
                  context,
                  DunesColors.border,
                  role: DunesColorRole.border,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text(
              '全选',
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onClearAll,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: DunesColors.resolve(
                  context,
                  DunesColors.border,
                  role: DunesColorRole.border,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text(
              '清空已选',
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.resolve(context, DunesColors.text2),
                context: context,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatDeptBlock extends StatefulWidget {
  const _NewChatDeptBlock({
    super.key,
    required this.department,
    required this.currentUserId,
    required this.selectedUserIds,
    required this.onlineUsers,
    required this.avatarService,
    required this.onToggleContact,
  });

  final NativeDepartment department;
  final int currentUserId;
  final Set<int> selectedUserIds;
  final Set<int> onlineUsers;
  final ConversationService avatarService;
  final ValueChanged<NativeContact> onToggleContact;

  @override
  State<_NewChatDeptBlock> createState() => _NewChatDeptBlockState();
}

class _NewChatDeptBlockState extends State<_NewChatDeptBlock> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.department.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final dep = widget.department;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: ImTapScale(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ImVisualTokens.cardSurface(context),
                border: Border.all(
                  color: ImVisualTokens.hairlineBorder(context),
                  width: 0.7,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: ImVisualTokens.fastAnim,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: ImVisualTokens.accentSoftSurface(context),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.business_rounded,
                      size: 15,
                      color: ImVisualTokens.accent(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dep.name,
                          style: DunesTypography.sans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            context: context,
                          ),
                        ),
                        if ((dep.subtitle ?? '').isNotEmpty)
                          Text(
                            dep.subtitle!,
                            style: DunesTypography.sans(
                              fontSize: 11.5,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                              context: context,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: ImVisualTokens.accentSoftSurface(context),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${dep.userCount}',
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ImVisualTokens.accentText(context),
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Column(
              children: [
                ...dep.users
                    .where(
                      (c) =>
                          c.userId > 0 &&
                          c.userId != widget.currentUserId &&
                          c.enabled,
                    )
                    .map(
                      (c) => _NewChatPickRow(
                        contact: c,
                        selected: widget.selectedUserIds.contains(c.userId),
                        online: widget.onlineUsers.contains(c.userId),
                        avatarService: widget.avatarService,
                        onTap: () => widget.onToggleContact(c),
                      ),
                    ),
                ...dep.children.map(
                  (child) => _NewChatDeptBlock(
                    key: ValueKey('dept-${child.id}'),
                    department: child,
                    currentUserId: widget.currentUserId,
                    selectedUserIds: widget.selectedUserIds,
                    onlineUsers: widget.onlineUsers,
                    avatarService: widget.avatarService,
                    onToggleContact: widget.onToggleContact,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NewChatPickRow extends StatelessWidget {
  const _NewChatPickRow({
    required this.contact,
    required this.selected,
    required this.online,
    required this.avatarService,
    required this.onTap,
  });

  final NativeContact contact;
  final bool selected;
  final bool online;
  final ConversationService avatarService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = <Widget>[];
    if (contact.primaryRole.isNotEmpty) {
      meta.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.bgSoft,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                DunesColors.borderSoft,
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Text(
            contact.primaryRole,
            style: DunesTypography.mono(
              fontSize: 8.5,
              color: DunesColors.resolve(context, DunesColors.text2),
              context: context,
            ),
          ),
        ),
      );
    }
    if ((contact.department ?? '').trim().isNotEmpty) {
      meta.add(
        Text(
          contact.department!.trim(),
          style: DunesTypography.mono(
            fontSize: 9,
            color: DunesColors.resolve(context, DunesColors.text3),
            context: context,
          ),
        ),
      );
    }
    return ImTapScale(
      borderRadius: BorderRadius.zero,
      pressedScale: 0.992,
      onTap: onTap,
      child: AnimatedContainer(
        duration: ImVisualTokens.fastAnim,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? ImVisualTokens.accentSoftSurface(context).withValues(alpha: 0.55)
              : ImVisualTokens.cardSurface(context),
          border: Border(
            bottom: BorderSide(
              color: ImVisualTokens.hairlineBorder(context),
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            ImSelectCircle(selected: selected, size: 21),
            const SizedBox(width: 10),
            ImUserAvatar(
              initial: contact.displayLabel.isNotEmpty
                  ? contact.displayLabel.substring(0, 1)
                  : '?',
              seed: contact.userId,
              size: 36,
              showOnline: online,
              avatarPreset: contact.avatarPreset,
              avatarObjectKey: contact.avatarObjectKey,
              avatarService: avatarService,
              borderRadius: 36 * 0.22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayLabel,
                    style: DunesTypography.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 5,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: meta,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
