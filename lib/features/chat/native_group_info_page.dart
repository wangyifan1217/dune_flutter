import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
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
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final VoidCallback onBack;
  final ValueChanged<int>? onOpenSearch;
  final ValueChanged<int>? onOpenMedia;
  final void Function(int userId, String displayName)? onOpenMember;
  final VoidCallback? onOpenApproval;
  final VoidCallback? onExitedGroup;

  @override
  State<NativeGroupInfoPage> createState() => _NativeGroupInfoPageState();
}

class _NativeGroupInfoPageState extends State<NativeGroupInfoPage> {
  late final ConversationService _service;
  late final ContactService _contacts;

  bool _loading = true;
  String? _error;
  NativeGroupInfo? _info;
  int _mediaCount = 0;
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
      final results = await Future.wait<dynamic>([
        _service.fetchGroupInfo(convId),
        _service.fetchMediaCount(convId),
      ]);
      final info = results[0] as NativeGroupInfo;
      final mediaCount = results[1] as int;
      Map<String, dynamic>? linked;
      if (info.hasLinkedApproval) {
        linked = await _service.fetchApprovalTrail(info.businessType!, info.businessId!);
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _mediaCount = mediaCount;
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
    try {
      await _service.patchMySettings(info.id, muted: !info.muted);
      if (!mounted) return;
      setState(() => _info = NativeGroupInfo(
            id: info.id,
            kind: info.kind,
            title: info.title,
            members: info.members,
            muted: !info.muted,
            pinned: info.pinned,
            isOwner: info.isOwner,
            canLeave: info.canLeave,
            dissolved: info.dissolved,
            createdAt: info.createdAt,
            businessType: info.businessType,
            businessId: info.businessId,
          ));
    } catch (e) {
      if (!mounted) return;
      _toast(context, '设置失败');
    }
  }

  Future<void> _togglePinned() async {
    final info = _detail;
    if (info == null) return;
    try {
      await _service.patchMySettings(info.id, pinned: !info.pinned);
      if (!mounted) return;
      setState(() => _info = NativeGroupInfo(
            id: info.id,
            kind: info.kind,
            title: info.title,
            members: info.members,
            muted: info.muted,
            pinned: !info.pinned,
            isOwner: info.isOwner,
            canLeave: info.canLeave,
            dissolved: info.dissolved,
            createdAt: info.createdAt,
            businessType: info.businessType,
            businessId: info.businessId,
          ));
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
      widget.onExitedGroup?.call();
    } catch (e) {
      if (!mounted) return;
      _toast(context, friendlyErrorText(e));
    }
  }

  Future<void> _openAddMembers() async {
    final info = _detail;
    if (info == null || !info.isOwner) {
      _toast(context, '仅群主可添加成员');
      return;
    }
    final exclude = info.members.map((m) => m.userId).toSet();
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPickerSheet(
        contacts: _contacts,
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
      backgroundColor: const Color(0xFFE8E4D9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatConvHeader(
              title: '群信息',
              subtitle: info != null ? _headerSubtitle(info) : '${hint.memberCount} 成员',
              onBack: widget.onBack,
            ),
            Expanded(child: _buildBody(hint)),
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
    final canLeave = info.canLeave || info.dissolved;

    return ListView(
      children: [
        GroupInfoHero(
          title: info.title,
          subtitle: groupInfoHeroSubtitle(info),
          icon: groupInfoHeroIcon(info.kind),
        ),
        if (info.hasLinkedApproval) ...[
          const GroupInfoSectionLabel('关联审批'),
          _buildLinkedApproval(info),
        ],
        GroupInfoSectionLabel('群成员 · ${members.length} 人'),
        GroupInfoMemberGrid(
          members: members,
          selfUserId: widget.session.userId,
          showAdd: showOwnerActions,
          showRemove: showOwnerActions,
          onMemberTap: widget.onOpenMember == null
              ? null
              : (m) => widget.onOpenMember!(m.userId, m.displayName),
          onAdd: _openAddMembers,
          onRemove: _openRemoveMember,
        ),
        const GroupInfoSectionLabel('群设置'),
        GroupInfoRow(
          icon: Icons.edit_outlined,
          title: '群名称',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  info.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.mono(fontSize: 10.5, color: DunesColors.text2),
                ),
              ),
              const GroupInfoChevron(),
            ],
          ),
          onTap: _renameGroup,
        ),
        GroupInfoRow(
          icon: Icons.qr_code_2_outlined,
          title: '群二维码',
          trailing: const GroupInfoChevron(),
          onTap: () => _toast(context, '群二维码功能即将上线'),
        ),
        GroupInfoRow(
          icon: Icons.notifications_off_outlined,
          title: '消息免打扰',
          subtitle: '仅 @我 时提醒',
          trailing: GroupInfoToggle(value: info.muted),
          onTap: _toggleMuted,
        ),
        GroupInfoRow(
          icon: Icons.push_pin_outlined,
          title: '置顶聊天',
          trailing: GroupInfoToggle(value: info.pinned),
          onTap: _togglePinned,
        ),
        const GroupInfoSectionLabel('聊天记录'),
        GroupInfoRow(
          icon: Icons.search,
          title: '查找聊天内容',
          trailing: const GroupInfoChevron(),
          onTap: widget.onOpenSearch == null ? null : () => widget.onOpenSearch!(info.id),
        ),
        GroupInfoRow(
          icon: Icons.photo_outlined,
          title: '图片、视频、文件',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_mediaCount',
                style: DunesTypography.mono(fontSize: 10.5, color: DunesColors.text2),
              ),
              const GroupInfoChevron(),
            ],
          ),
          onTap: widget.onOpenMedia == null ? null : () => widget.onOpenMedia!(info.id),
        ),
        const GroupInfoSectionLabel(''),
        if (showOwnerActions)
          GroupInfoDangerRow(label: '解散该群', onTap: _confirmDissolve),
        if (canLeave)
          GroupInfoDangerRow(
            label: info.dissolved ? '退出已解散群聊' : '退出该群',
            onTap: _confirmLeave,
          ),
        const SizedBox(height: 24),
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
    required this.session,
    required this.title,
    required this.multi,
    this.excludeIds,
    this.candidates,
  });

  final ContactService contacts;
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
  bool _loading = true;
  List<NativeContact> _rows = const <NativeContact>[];

  @override
  void initState() {
    super.initState();
    if (widget.candidates != null) {
      _rows = widget.candidates!
          .map((m) => NativeContact(userId: m.userId, displayName: m.displayName, title: m.role))
          .toList();
      _loading = false;
    } else {
      _load('');
    }
    _search.addListener(() => _load(_search.text.trim()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    if (widget.candidates != null) {
      final query = q.toLowerCase();
      setState(() {
        _rows = widget.candidates!
            .where((m) => query.isEmpty || m.displayName.toLowerCase().contains(query))
            .map((m) => NativeContact(userId: m.userId, displayName: m.displayName, title: m.role))
            .toList();
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await widget.contacts.fetchContacts(keyword: q);
      final exclude = widget.excludeIds ?? const <int>{};
      final me = widget.session.userId;
      if (!mounted) return;
      setState(() {
        _rows = items
            .where((c) => c.userId > 0 && c.userId != me && !exclude.contains(c.userId) && c.enabled != false)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const <NativeContact>[];
        _loading = false;
      });
    }
  }

  void _toggle(int userId) {
    setState(() {
      if (widget.multi) {
        if (_selected.contains(userId)) {
          _selected.remove(userId);
        } else {
          _selected.add(userId);
        }
      } else {
        _selected
          ..clear()
          ..add(userId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.2),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: '搜索姓名 / 部门',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: DunesColors.bgSoft,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
                  : _rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('无匹配联系人', style: TextStyle(color: DunesColors.text3)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final c = _rows[i];
                            final on = _selected.contains(c.userId);
                            return Material(
                              color: DunesColors.bgApp,
                              child: InkWell(
                                onTap: () {
                                  if (widget.multi) {
                                    _toggle(c.userId);
                                  } else {
                                    Navigator.pop(context, c.userId);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
                                  ),
                                  child: Row(
                                    children: [
                                      ChatPersonAvatar(
                                        initial: c.displayName.isNotEmpty ? c.displayName.substring(0, 1) : '?',
                                        seed: c.userId,
                                        size: 34,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.displayName,
                                              style: DunesTypography.sans(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                                color: DunesColors.text,
                                              ),
                                            ),
                                            if ((c.title ?? c.department ?? '').trim().isNotEmpty)
                                              Text(
                                                (c.title ?? c.department)!.trim(),
                                                style: DunesTypography.mono(
                                                  fontSize: 9,
                                                  color: DunesColors.text3,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (widget.multi)
                                        Icon(
                                          on ? Icons.check_circle : Icons.circle_outlined,
                                          color: DunesColors.accent,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (widget.multi)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
                    child: Text('确定${_selected.isEmpty ? '' : ' (${_selected.length})'}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
