import 'package:flutter/material.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../contacts/contacts_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_hidden_storage.dart';
import '../shell/dunes_toast.dart';
import 'chat_widgets.dart';
import 'group_info_widgets.dart';

void _toast(BuildContext context, String message) {
  showDunesToast(
    context,
    message,
    kind: dunesToastLooksLikeError(message)
        ? DunesToastKind.error
        : DunesToastKind.normal,
  );
}

class NativeGroupInfoPage extends StatefulWidget {
  const NativeGroupInfoPage({
    super.key,
    required this.session,
    required this.conversationHint,
    required this.onBack,
    this.onOpenSearch,
    this.onOpenMedia,
    this.onOpenMember,
    this.onOpenApproval,
    this.onExitedGroup,
    this.onChatSettingsChanged,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final VoidCallback onBack;
  final ValueChanged<int>? onOpenSearch;
  final ValueChanged<int>? onOpenMedia;
  final void Function(int userId, String displayName)? onOpenMember;
  final VoidCallback? onOpenApproval;
  final ValueChanged<int>? onExitedGroup;
  final void Function({required int conversationId, bool? muted, bool? pinned})?
      onChatSettingsChanged;

  @override
  State<NativeGroupInfoPage> createState() => _NativeGroupInfoPageState();
}

class _NativeGroupInfoPageState extends State<NativeGroupInfoPage> {
  late final ConversationService _service;
  late final ContactService _contacts;

  bool _loading = true;
  String? _error;
  NativeGroupInfo? _info;
  Map<String, dynamic>? _linkedApproval;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _contacts = ContactService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final convId = widget.conversationHint.id;
      final info = await _service.fetchGroupInfo(convId);
      Map<String, dynamic>? linked;
      if (info.hasLinkedApproval) {
        linked = await _service.fetchApprovalTrail(info.businessType!, info.businessId!);
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _linkedApproval = linked;
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

  NativeGroupInfo? get _detail => _info;

  String _headerSubtitle(NativeGroupInfo info) {
    return '${info.kindLabel} · ${info.members.length} 成员';
  }

  Future<void> _toggleMuted() async {
    final info = _detail;
    if (info == null) return;
    final nextMuted = !info.muted;
    try {
      await _service.patchMySettings(info.id, muted: nextMuted);
      if (!mounted) return;
      setState(() => _info = NativeGroupInfo(
            id: info.id,
            kind: info.kind,
            title: info.title,
            members: info.members,
            muted: nextMuted,
            pinned: info.pinned,
            isOwner: info.isOwner,
            canLeave: info.canLeave,
            dissolved: info.dissolved,
            createdAt: info.createdAt,
            businessType: info.businessType,
            businessId: info.businessId,
          ));
      widget.onChatSettingsChanged?.call(
        conversationId: info.id,
        muted: nextMuted,
        pinned: info.pinned,
      );
    } catch (e) {
      if (!mounted) return;
      _toast(context, '设置失败');
    }
  }

  Future<void> _togglePinned() async {
    final info = _detail;
    if (info == null) return;
    final nextPinned = !info.pinned;
    try {
      await _service.patchMySettings(info.id, pinned: nextPinned);
      if (!mounted) return;
      setState(() => _info = NativeGroupInfo(
            id: info.id,
            kind: info.kind,
            title: info.title,
            members: info.members,
            muted: info.muted,
            pinned: nextPinned,
            isOwner: info.isOwner,
            canLeave: info.canLeave,
            dissolved: info.dissolved,
            createdAt: info.createdAt,
            businessType: info.businessType,
            businessId: info.businessId,
          ));
      widget.onChatSettingsChanged?.call(
        conversationId: info.id,
        muted: info.muted,
        pinned: nextPinned,
      );
    } catch (e) {
      if (!mounted) return;
      _toast(context, '设置失败');
    }
  }

  Future<void> _renameGroup() async {
    final info = _detail;
    if (info == null) return;
    if (!info.isOwner) {
      _toast(context, '仅群主可修改群名称');
      return;
    }
    final controller = TextEditingController(text: info.title);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改群名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '群名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (next == null) return;
    if (next.isEmpty) {
      if (mounted) _toast(context, '群名称不能为空');
      return;
    }
    try {
      await _service.patchConversationTitle(info.id, next);
      if (!mounted) return;
      _toast(context, '群名称已更新');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  Future<void> _confirmDissolve() async {
    final info = _detail;
    if (info == null || !info.isOwner) {
      _toast(context, '仅群主可解散群聊');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: const Text('解散后群聊仍保留历史记录，但所有成员将无法再发送消息或操作群设置。确定解散？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.dissolveGroup(info.id);
      if (!mounted) return;
      _toast(context, '群聊已解散');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  Future<void> _confirmLeave() async {
    final info = _detail;
    if (info == null) return;
    if (!info.canLeave && !info.dissolved) {
      _toast(context, '系统群不可退出');
      return;
    }
    final dissolved = info.dissolved;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dissolved ? '退出已解散群聊' : '退出群聊'),
        content: Text(dissolved ? '该群已解散，退出后将从你的会话列表中移除。确定退出？' : '确定退出该群聊？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final serverRemoved = await _service.exitGroupMembership(info.id, dissolved: dissolved);
      final permanent = dissolved || !serverRemoved;
      await InboxHiddenStorage.hide(info.id, permanent: permanent);
      if (!mounted) return;
      _toast(context, dissolved ? '该群已解散，已为你退出' : '已退出群聊');
      widget.onExitedGroup?.call(info.id);
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  Future<void> _openAddMembers() async {
    final info = _detail;
    if (info == null || info.dissolved) {
      if (info != null && info.dissolved) {
        _toast(context, '群聊已解散');
      }
      return;
    }
    final exclude = info.members.map((m) => m.userId).toSet();
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(
        contacts: _contacts,
        avatarService: _service,
        session: widget.session,
        excludeIds: exclude,
        title: '从通讯录选择成员',
        multi: true,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      final added = await _service.addGroupMembers(info.id, picked);
      if (!mounted) return;
      _toast(context, '已添加 $added 人');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  Future<void> _openRemoveMember() async {
    final info = _detail;
    if (info == null || !info.isOwner) {
      _toast(context, '仅群主可移除成员');
      return;
    }
    final candidates = info.members.where((m) => m.userId != widget.session.userId).toList();
    if (candidates.isEmpty) {
      _toast(context, '暂无可移除成员');
      return;
    }
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(
        contacts: _contacts,
        avatarService: _service,
        session: widget.session,
        candidates: candidates,
        title: '选择要移除的成员',
        multi: true,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    try {
      for (final userId in picked) {
        await _service.removeGroupMember(info.id, userId);
      }
      if (!mounted) return;
      _toast(context, '已移除 ${picked.length} 人');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.conversationHint;
    final info = _detail;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatConvHeader(
              title: '聊天信息',
              subtitle: info != null ? _headerSubtitle(info) : '${hint.memberCount} 成员',
              onBack: widget.onBack,
            ),
            Expanded(
              child: groupInfoPageShell(child: _buildBody(hint)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(NativeConversation hint) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text3, fontSize: 12)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final info = _detail!;
    final members = sortGroupMembers(info.members);
    final showOwnerActions = info.isOwner && !info.dissolved;
    final showAdd = !info.dissolved;
    final canLeave = info.canLeave || info.dissolved;
    final wide = isWideChatLayout(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        GroupInfoHero(
          title: info.title,
          subtitle: groupInfoHeroSubtitle(info),
          icon: groupInfoHeroIcon(info.kind),
        ),
        const SizedBox(height: 10),
        GroupInfoMemberGrid(
          members: members,
          avatarService: _service,
          showAdd: showAdd,
          showRemove: showOwnerActions,
          onMemberTap: widget.onOpenMember == null
              ? null
              : (m) => widget.onOpenMember!(m.userId, m.displayName),
          onAdd: _openAddMembers,
          onRemove: _openRemoveMember,
        ),
        if (info.hasLinkedApproval) ...[
          const GroupInfoSectionLabel('关联审批'),
          _buildLinkedApproval(info),
        ],
        const SizedBox(height: 10),
        GroupInfoRow(
          icon: Icons.edit_outlined,
          title: '群聊名称',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 320 : 160),
                child: Text(
                  info.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: DunesTypography.sans(
                    fontSize: 15,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              if (!wide) const GroupInfoChevron(),
            ],
          ),
          onTap: _renameGroup,
        ),
        if (!wide)
          GroupInfoRow(
            icon: Icons.qr_code_2_outlined,
            title: '群二维码',
            trailing: const GroupInfoChevron(),
            onTap: () => _toast(context, '群二维码功能即将上线'),
          )
        else
          GroupInfoRow(
            icon: Icons.qr_code_2_outlined,
            title: '群二维码',
            trailing: Text(
              '即将上线',
              style: DunesTypography.sans(
                fontSize: 15,
                color: const Color(0xFF888888),
              ),
            ),
          ),
        const SizedBox(height: 10),
        GroupInfoRow(
          icon: Icons.notifications_off_outlined,
          title: '消息免打扰',
          trailing: GroupInfoToggle(value: info.muted),
          onTap: _toggleMuted,
        ),
        GroupInfoRow(
          icon: Icons.push_pin_outlined,
          title: '置顶聊天',
          trailing: GroupInfoToggle(value: info.pinned),
          onTap: _togglePinned,
        ),
        const SizedBox(height: 10),
        GroupInfoRow(
          icon: Icons.search,
          title: '查找聊天内容',
          trailing: const GroupInfoChevron(),
          onTap: widget.onOpenSearch == null ? null : () => widget.onOpenSearch!(info.id),
        ),
        if (showOwnerActions)
          GroupInfoDangerRow(label: '解散群聊', onTap: _confirmDissolve),
        if (canLeave)
          GroupInfoDangerRow(
            label: info.dissolved ? '退出已解散群聊' : '删除并退出',
            onTap: _confirmLeave,
          ),
      ],
    );
  }

  Widget _buildLinkedApproval(NativeGroupInfo info) {
    final trail = _linkedApproval;
    final bt = info.businessType ?? '';
    final bid = info.businessId ?? '';
    if (trail == null) {
      return GroupInfoRow(
        icon: Icons.assignment_outlined,
        title: '$bt #$bid',
        subtitle: '暂无关联审批数据',
        accentIcon: true,
      );
    }
    final title = (trail['title'] ?? trail['name'] ?? '').toString();
    final status = (trail['status'] ?? trail['currentNode'] ?? '').toString();
    final route = (trail['routeType'] ?? trail['kind'] ?? bt).toString();
    final steps = trail['steps'] ?? trail['items'];
    final stepCount = steps is List ? steps.length : 0;
    return Column(
      children: [
        GroupInfoRow(
          icon: Icons.assignment_outlined,
          title: '$bt #$bid · $title',
          subtitle: status.isEmpty ? route : '$route · $status',
          accentIcon: true,
          trailing: const GroupInfoChevron(),
          onTap: widget.onOpenApproval,
        ),
        if (stepCount > 0)
          GroupInfoRow(
            icon: Icons.route_outlined,
            title: '审批节点 · $stepCount 步',
            subtitle: _lastStepLabel(steps as List),
          ),
      ],
    );
  }

  String _lastStepLabel(List steps) {
    if (steps.isEmpty) return '';
    final last = steps.last;
    if (last is Map) {
      return (last['node'] ?? last['name'] ?? '').toString();
    }
    return '';
  }
}


class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({
    required this.contacts,
    required this.avatarService,
    required this.session,
    required this.title,
    required this.multi,
    this.excludeIds,
    this.candidates,
  });

  final ContactService contacts;
  final ConversationService avatarService;
  final AuthSession session;
  final String title;
  final bool multi;
  final Set<int>? excludeIds;
  final List<NativeGroupMember>? candidates;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final _search = TextEditingController();
  final _selected = <int>{};
  final _contactById = <int, NativeContact>{};
  bool _loading = true;
  List<NativeContact> _rows = const <NativeContact>[];
  List<NativeDepartment> _departments = const <NativeDepartment>[];

  bool get _isRemoveMode => widget.candidates != null;

  bool _isEligible(NativeContact c) {
    if (c.userId <= 0 || c.userId == widget.session.userId || c.enabled == false) {
      return false;
    }
    final exclude = widget.excludeIds;
    if (exclude != null && exclude.contains(c.userId)) return false;
    return true;
  }

  String? _cleanJob(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final upper = v.toUpperCase();
    if (upper == 'MEMBER' || upper == 'OWNER' || upper == 'ADMIN') return null;
    return v;
  }

  NativeContact _contactFromMember(NativeGroupMember m) {
    final enriched = _contactById[m.userId];
    final title = _cleanJob(m.title) ??
        _cleanJob(enriched?.title) ??
        _cleanJob(m.roleLabel) ??
        _cleanJob(enriched?.roleLabel);
    final department = (m.department ?? '').trim().isNotEmpty
        ? m.department!.trim()
        : ((enriched?.department ?? '').trim().isNotEmpty
            ? enriched!.department!.trim()
            : null);
    return NativeContact(
      userId: m.userId,
      displayName: m.displayName,
      title: title,
      department: department,
      roleLabel: m.roleLabel,
      avatarPreset: m.avatarPreset ?? enriched?.avatarPreset,
      avatarObjectKey: m.avatarObjectKey ?? enriched?.avatarObjectKey,
    );
  }

  void _rememberContacts(Iterable<NativeContact> rows) {
    for (final c in rows) {
      if (c.userId > 0) _contactById[c.userId] = c;
    }
  }

  void _rememberDepartments(List<NativeDepartment> deps) {
    for (final d in deps) {
      _rememberContacts(d.users);
      _rememberDepartments(d.children);
    }
  }

  NativeDepartment? _filterDept(NativeDepartment dep) {
    final users = dep.users.where(_isEligible).toList(growable: false);
    final children = dep.children
        .map(_filterDept)
        .whereType<NativeDepartment>()
        .toList(growable: false);
    if (users.isEmpty && children.isEmpty) return null;
    final count = users.length +
        children.fold<int>(0, (n, c) => n + c.userCount);
    return NativeDepartment(
      id: dep.id,
      name: dep.name,
      subtitle: dep.subtitle,
      userCount: count,
      expanded: true,
      users: users,
      children: children,
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _search.addListener(() => _load(_search.text.trim()));
  }

  Future<void> _bootstrap() async {
    if (_isRemoveMode) {
      setState(() => _loading = true);
      try {
        final org = await widget.contacts.fetchOrgContacts();
        if (!mounted) return;
        _rememberContacts(org.searchItems);
        _rememberDepartments(org.departments);
      } catch (_) {
        // 通讯录补全失败时仍展示成员基础信息
      }
      if (!mounted) return;
      setState(() {
        _rows = widget.candidates!.map(_contactFromMember).toList(growable: false);
        _loading = false;
      });
      return;
    }
    await _load('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    if (_isRemoveMode) {
      final query = q.toLowerCase();
      setState(() {
        _rows = widget.candidates!
            .where((m) {
              if (query.isEmpty) return true;
              final c = _contactFromMember(m);
              return m.displayName.toLowerCase().contains(query) ||
                  (c.department ?? '').toLowerCase().contains(query) ||
                  (c.title ?? '').toLowerCase().contains(query);
            })
            .map(_contactFromMember)
            .toList(growable: false);
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final org = await widget.contacts.fetchOrgContacts(keyword: q);
      if (!mounted) return;
      _rememberContacts(org.searchItems);
      _rememberDepartments(org.departments);
      if (q.isNotEmpty) {
        setState(() {
          _rows = org.searchItems.where(_isEligible).toList(growable: false);
          _departments = const <NativeDepartment>[];
          _loading = false;
        });
      } else {
        setState(() {
          _departments = org.departments
              .map(_filterDept)
              .whereType<NativeDepartment>()
              .toList(growable: false);
          _rows = const <NativeContact>[];
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const <NativeContact>[];
        _departments = const <NativeDepartment>[];
        _loading = false;
      });
    }
  }

  void _toggle(NativeContact c) {
    setState(() {
      if (widget.multi) {
        if (_selected.contains(c.userId)) {
          _selected.remove(c.userId);
        } else {
          _selected.add(c.userId);
        }
      } else {
        _selected
          ..clear()
          ..add(c.userId);
      }
    });
  }

  Widget _buildListBody() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final searching = _search.text.trim().isNotEmpty || _isRemoveMode;
    if (searching) {
      if (_rows.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _isRemoveMode ? '暂无可移除成员' : '无匹配联系人',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _rows.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 66,
                      color: Color(0xFFF0F1F3),
                    ),
                  ContactRowTile(
                    contact: _rows[i],
                    currentUserId: widget.session.userId,
                    onOpenProfile: () {},
                    onMessage: () {},
                    avatarService: widget.avatarService,
                    pickMode: true,
                    selected: _selected.contains(_rows[i].userId),
                    onToggleSelect: () => _toggle(_rows[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    if (_departments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '暂无可添加的同事',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }
    // 与通讯录选人一致的行组件，部门以独立圆角卡片铺开（对齐加人截图）。
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final dep in _departments)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F1F3),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: DeptBlockTile(
              department: dep,
              currentUserId: widget.session.userId,
              onOpenContact: (_) {},
              onMessageContact: (_) {},
              avatarService: widget.avatarService,
              pickMode: true,
              selectedUserIds: _selected,
              onToggleContact: _toggle,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.12),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEEF1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 18, color: DunesColors.text3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          style: DunesTypography.sans(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '搜索姓名 / 部门',
                            hintStyle: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _buildListBody()),
              if (widget.multi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, _selected.toList()),
                      style: FilledButton.styleFrom(
                        backgroundColor: DunesColors.accent,
                        disabledBackgroundColor: const Color(0xFFD8D8D8),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF888888),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: Text(
                        _selected.isEmpty ? '确定' : '确定（）',
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
