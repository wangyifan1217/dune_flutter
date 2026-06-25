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
  Set<int> _onlineUsers = <int>{};
  Set<int> _selectedUserIds = <int>{};
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
      final data = await _service.fetchOrgContacts(keyword: _searchController.text);
      if (!mounted) return;
      setState(() {
        _total = data.total;
        if (!searching) _departments = data.departments;
        _searchItems = data.searchItems.where((c) => c.enabled && c.userId != widget.session.userId).toList(growable: false);
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
    if (!contact.enabled || contact.userId <= 0 || contact.userId == widget.session.userId) return;
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
    setState(() {
      if (_mode == _NewChatMode.private) {
        _selectedUserIds = contacts.isEmpty ? <int>{} : <int>{contacts.first.userId};
      } else {
        _selectedUserIds = contacts.map((c) => c.userId).where((id) => id > 0 && id != widget.session.userId).toSet();
      }
    });
  }

  void _clearSelected() {
    setState(() => _selectedUserIds = <int>{});
  }

  List<NativeContact> _allSelectableContacts() {
    final all = <NativeContact>[];
    void walk(NativeDepartment dep) {
      all.addAll(dep.users.where((c) => c.enabled && c.userId != widget.session.userId));
      for (final child in dep.children) {
        walk(child);
      }
    }
    for (final dep in _departments) {
      walk(dep);
    }
    final seen = <int>{};
    final deduped = all.where((c) => seen.add(c.userId)).toList(growable: false);
    if (deduped.isNotEmpty) return deduped;
    return _searchItems.where((c) => seen.add(c.userId)).toList(growable: false);
  }

  NativeContact? _contactById(int userId) {
    for (final c in _searchItems) {
      if (c.userId == userId) return c;
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
    return hit;
  }

  Future<void> _createConversation() async {
    if (_creating) return;
    final ids = _selectedUserIds.where((id) => id > 0 && id != widget.session.userId).toList(growable: false);
    if (ids.isEmpty) {
      showDunesSoonToast(context, '请至少选择一位同事');
      return;
    }
    setState(() => _creating = true);
    try {
      if (_mode == _NewChatMode.private || ids.length == 1) {
        final peerId = ids.first;
        final convId = await _conversationService.ensurePrivateConversationForPeer(peerId);
        if (!mounted) return;
        if (convId == null || convId <= 0) throw Exception('创建私聊失败');
        widget.onOpenPrivateChat(peerId);
        return;
      }
      final title = ids.take(3).map((id) => _contactById(id)?.displayName ?? '成员').join('、');
      final conversation = await _conversationService.createConversation(
        kind: 'WORKGROUP',
        memberUserIds: ids,
        title: title.isEmpty ? '群聊' : title,
      );
      if (!mounted) return;
      if (conversation == null) throw Exception('创建群聊失败');
      widget.onOpenGroupChat(conversation);
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '创建会话失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            _NewChatHeader(onBack: widget.onBack, creating: _creating, onCreate: _createConversation),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 4),
              child: _NewChatModeGrid(mode: _mode, onPick: _toggleMode),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: DunesColors.bgSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: DunesColors.text3),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) => _load(),
                        style: DunesTypography.sans(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜索同事 · 部门 · 角色',
                          hintStyle: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _NewChatSelectedStack(
              selectedUserIds: _selectedUserIds.toList()..sort(),
              resolveContact: _contactById,
              onRemove: (userId) => setState(() => _selectedUserIds.remove(userId)),
            ),
            _NewChatBulkBar(
              onSelectAll: _selectAllMembers,
              onClearAll: _clearSelected,
              privateMode: _mode == _NewChatMode.private,
            ),
            _NewChatOrgLabel(total: _total),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: DunesColors.text3)))
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
        return const Center(child: Text('无匹配联系人', style: TextStyle(color: DunesColors.text3)));
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
    if (_departments.isEmpty) {
      return const Center(child: Text('暂无组织数据', style: TextStyle(color: DunesColors.text3)));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: _departments
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
    );
  }
}

class _NewChatOrgLabel extends StatelessWidget {
  const _NewChatOrgLabel({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: [
          Text(
            '组织树',
            style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600, color: DunesColors.accent),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              height: 1,
              color: DunesColors.borderSoft,
            ),
          ),
          Text('$total 人', style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 24),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新建会话', style: DunesTypography.sans(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('选择成员 · 单聊 / 群聊', style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
              ],
            ),
          ),
          TextButton(
            onPressed: creating ? null : onCreate,
            style: TextButton.styleFrom(
              backgroundColor: DunesColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: DunesTypography.mono(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            child: Text(creating ? '创建中' : '创建'),
          ),
        ],
      ),
    );
  }
}

class _NewChatModeGrid extends StatelessWidget {
  const _NewChatModeGrid({
    required this.mode,
    required this.onPick,
  });

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
    final borderColor = selected ? DunesColors.accentLine : DunesColors.border;
    final iconBg = selected ? DunesColors.accent : DunesColors.bgSoft;
    final iconColor = selected ? Colors.white : DunesColors.text2;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor),
            gradient: selected
                ? LinearGradient(colors: [DunesColors.accentSoft, DunesColors.bgApp])
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: selected ? DunesColors.accent : DunesColors.borderSoft),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: DunesTypography.sans(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: DunesTypography.mono(fontSize: 8.5, color: DunesColors.text3)),
                  ],
                ),
              ),
            ],
          ),
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
      decoration: const BoxDecoration(
        color: DunesColors.bgSoft,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
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
              color: DunesColors.text3,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.04 * 9,
            ),
          ),
          if (selectedUserIds.isEmpty)
            Text('请从组织树选择成员', style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3))
          else
            ...selectedUserIds.map((id) {
              final name = resolveContact(id)?.displayName ?? '成员$id';
              return InkWell(
                onTap: () => onRemove(id),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DunesColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, style: DunesTypography.sans(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.close_rounded, size: 12, color: Colors.white70),
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
              side: const BorderSide(color: DunesColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text('全选', style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onClearAll,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: DunesColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            child: Text('清空已选', style: DunesTypography.sans(fontSize: 11, color: DunesColors.text2)),
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
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [DunesColors.bgSoft, DunesColors.bgApp.withValues(alpha: 0.2)]),
                border: Border.all(color: DunesColors.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right, size: 13, color: DunesColors.text3),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: DunesColors.accentSoft,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: DunesColors.borderSoft),
                    ),
                    child: const Icon(Icons.business_outlined, size: 13, color: DunesColors.accentDeep),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dep.name, style: DunesTypography.sans(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        if ((dep.subtitle ?? '').isNotEmpty)
                          Text(dep.subtitle!, style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3)),
                      ],
                    ),
                  ),
                  Text('${dep.userCount}', style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3)),
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
                    .where((c) => c.userId > 0 && c.userId != widget.currentUserId && c.enabled)
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
            color: DunesColors.bgSoft,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Text(contact.primaryRole, style: DunesTypography.mono(fontSize: 8.5, color: DunesColors.text2)),
        ),
      );
    }
    if ((contact.department ?? '').trim().isNotEmpty) {
      meta.add(Text(contact.department!.trim(), style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3)));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: const BoxDecoration(
            color: DunesColors.bgApp,
            border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? DunesColors.accent : Colors.white,
                  border: Border.all(color: selected ? DunesColors.accent : DunesColors.border),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
              ),
              const SizedBox(width: 10),
              ImUserAvatar(
                initial: contact.displayLabel.isNotEmpty ? contact.displayLabel.substring(0, 1) : '?',
                seed: contact.userId,
                size: 34,
                showOnline: online,
                avatarPreset: contact.avatarPreset,
                avatarObjectKey: contact.avatarObjectKey,
                avatarService: avatarService,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.displayLabel, style: DunesTypography.sans(fontSize: 11.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Wrap(spacing: 5, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: meta),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
