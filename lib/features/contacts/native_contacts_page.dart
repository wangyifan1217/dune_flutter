import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import 'contact_models.dart';
import 'contact_service.dart';
import 'contacts_widgets.dart';

class NativeContactsPage extends StatefulWidget {
  const NativeContactsPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenContact,
    required this.onStartPrivateChat,
    this.onOpenGroupChat,
    this.initialGroupPickMode = false,
    this.initialSelectedUserIds = const <int>{},
    this.lockedSelectedUserIds = const <int>{},
    this.initialSelectedNames = const <int, String>{},
    this.groupPickTitle = '创建群聊',
    this.groupPickSubtitle = '选择成员',
    this.minPickCount = 2,
    this.onPickCompleted,
    this.allowSelfInPickMode = false,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<int> onStartPrivateChat;
  final ValueChanged<NativeConversation>? onOpenGroupChat;
  final bool initialGroupPickMode;

  /// 进入建群多选时预勾选的成员（如私聊详情「+」带入的当前联系人）。
  final Set<int> initialSelectedUserIds;

  /// 不可取消勾选的成员（通常与 [initialSelectedUserIds] 中的发起人一致）。
  final Set<int> lockedSelectedUserIds;

  /// 预选成员展示名兜底（通讯录尚未加载完时用）。
  final Map<int, String> initialSelectedNames;

  /// 多选模式标题（如行政通知选人）。
  final String groupPickTitle;
  final String groupPickSubtitle;

  /// 完成多选所需最少人数；建群默认 2，行政通知等场景可设为 1。
  final int minPickCount;

  /// 非建群场景：点「完成」时回传已选 userId 与展示名，不再创建群聊。
  final void Function(Set<int> ids, Map<int, String> names)? onPickCompleted;

  /// 多选时是否允许勾选当前登录用户（如行政通知发给自己）。
  final bool allowSelfInPickMode;

  @override
  State<NativeContactsPage> createState() => _NativeContactsPageState();
}

class _NativeContactsPageState extends State<NativeContactsPage> {
  late final ContactService _service;
  late final ConversationService _convService;
  late final ConversationRealtimeService _realtime;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  StreamSubscription<Set<int>>? _onlineSub;

  bool _loading = true;
  bool _searchOpen = false;
  bool _groupPickMode = false;
  bool _creating = false;
  String? _error;
  int _total = 0;
  List<NativeDepartment> _departments = const <NativeDepartment>[];
  List<NativeContact> _searchItems = const <NativeContact>[];
  List<NativeContact> _externalContacts = const <NativeContact>[];
  int _externalTotal = 0;
  Set<int> _onlineUsers = <int>{};
  Set<int> _selectedUserIds = <int>{};
  /// 跨搜索保留已见过的联系人，避免已选成员头像/姓名退化成 userId。
  final Map<int, NativeContact> _knownContacts = <int, NativeContact>{};

  @override
  void initState() {
    super.initState();
    _groupPickMode = widget.initialGroupPickMode;
    if (_groupPickMode) {
      _selectedUserIds = _normalizedInitialSelected();
    }
    _seedInitialSelectedNames();
    _service = ContactService(session: widget.session);
    _convService = ConversationService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    _load();
    unawaited(_bootRealtime());
  }

  @override
  void didUpdateWidget(covariant NativeContactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroupPickMode != widget.initialGroupPickMode &&
        widget.initialGroupPickMode &&
        !_groupPickMode) {
      setState(() {
        _groupPickMode = true;
        _selectedUserIds = _normalizedInitialSelected();
      });
    } else if (widget.initialGroupPickMode &&
        (oldWidget.initialSelectedUserIds != widget.initialSelectedUserIds ||
            oldWidget.lockedSelectedUserIds != widget.lockedSelectedUserIds)) {
      setState(() {
        _selectedUserIds = {
          ..._selectedUserIds,
          ..._normalizedInitialSelected(),
        };
      });
    }
  }

  Set<int> _normalizedInitialSelected() {
    return widget.initialSelectedUserIds.where((id) {
      if (id <= 0) return false;
      if (widget.allowSelfInPickMode) return true;
      return id != widget.session.userId;
    }).toSet();
  }

  Set<int> get _lockedSelectedIds {
    return widget.lockedSelectedUserIds
        .where((id) => id > 0 && id != widget.session.userId)
        .toSet();
  }

  bool _isLockedSelected(int userId) => _lockedSelectedIds.contains(userId);

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
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keyword = _searchController.text;
      final data = await _service.fetchOrgContacts(keyword: keyword);
      final external = keyword.trim().isEmpty
          ? await _service.fetchExternalContacts()
          : await _service.fetchExternalContacts(keyword: keyword);
      if (!mounted) return;
      final searching = keyword.trim().isNotEmpty;
      setState(() {
        _total = data.total;
        _departments = data.departments;
        if (searching) {
          final seen = <int>{};
          _searchItems = [
            ...data.searchItems,
            ...external,
          ].where((c) => seen.add(c.userId)).toList(growable: false);
        } else {
          _searchItems = data.searchItems;
        }
        _externalContacts = external;
        _externalTotal = external.length;
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

  void _enterGroupPickMode() {
    setState(() {
      _groupPickMode = true;
      _selectedUserIds = <int>{};
      _searchOpen = true;
    });
  }

  void _handleBack() {
    if (_groupPickMode && !widget.initialGroupPickMode) {
      setState(() {
        _groupPickMode = false;
        _selectedUserIds = <int>{};
        _creating = false;
      });
      return;
    }
    widget.onBack();
  }

  void _toggleSelected(NativeContact contact) {
    if (!contact.enabled || contact.userId <= 0) {
      return;
    }
    if (!widget.allowSelfInPickMode && contact.userId == widget.session.userId) {
      return;
    }
    _rememberContacts([contact]);
    if (_selectedUserIds.contains(contact.userId)) {
      if (_isLockedSelected(contact.userId)) {
        showDunesToast(context, '当前会话联系人不可移除');
        return;
      }
      setState(() {
        _selectedUserIds = Set<int>.from(_selectedUserIds)
          ..remove(contact.userId);
      });
      return;
    }
    setState(() {
      _selectedUserIds = {..._selectedUserIds, contact.userId};
    });
  }

  void _removeSelected(int userId) {
    if (_isLockedSelected(userId)) {
      showDunesToast(context, '当前会话联系人不可移除', kind: DunesToastKind.normal);
      return;
    }
    setState(() => _selectedUserIds.remove(userId));
  }

  List<NativeContact> _allSelectableContacts() {
    final all = <NativeContact>[];
    bool selectable(NativeContact c) {
      if (!c.enabled || c.userId <= 0) return false;
      if (widget.allowSelfInPickMode) return true;
      return c.userId != widget.session.userId;
    }
    void walk(NativeDepartment dep) {
      all.addAll(dep.users.where(selectable));
      for (final child in dep.children) {
        walk(child);
      }
    }

    for (final dep in _departments) {
      walk(dep);
    }
    for (final c in _externalContacts) {
      if (selectable(c)) {
        all.add(c);
      }
    }
    final seen = <int>{};
    return all.where((c) => seen.add(c.userId)).toList(growable: false);
  }

  void _seedInitialSelectedNames() {
    widget.initialSelectedNames.forEach((id, name) {
      if (id <= 0 || _knownContacts.containsKey(id)) return;
      final trimmed = name.trim();
      if (trimmed.isEmpty) return;
      _knownContacts[id] = NativeContact(userId: id, displayName: trimmed);
    });
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
    if (hit != null) {
      _rememberContacts([hit!]);
      return hit;
    }
    final fallbackName = (widget.initialSelectedNames[userId] ?? '').trim();
    if (fallbackName.isEmpty) return null;
    return NativeContact(userId: userId, displayName: fallbackName);
  }

  void _selectAllMembers() {
    final contacts = _allSelectableContacts();
    _rememberContacts(contacts);
    setState(() {
      _selectedUserIds = contacts
          .map((c) => c.userId)
          .where((id) => id > 0)
          .toSet();
    });
  }

  void _clearSelected() {
    setState(() => _selectedUserIds = Set<int>.from(_lockedSelectedIds));
  }

  Future<void> _showSelectedMembersSheet() async {
    if (_selectedUserIds.isEmpty) {
      showDunesToast(context, '请先选择群成员');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _SelectedMembersSheet(
          selectedUserIds: _selectedUserIds,
          resolveContact: _contactById,
          avatarService: _convService,
          onRemove: (userId) {
            _removeSelected(userId);
            if (_selectedUserIds.isEmpty && sheetContext.mounted) {
              Navigator.pop(sheetContext);
            }
          },
          onDone: () => Navigator.pop(sheetContext),
        );
      },
    );
  }

  Future<void> _startPrivateChat(NativeContact contact) async {
    if (contact.userId <= 0) return;
    if (contact.userId == widget.session.userId) {
      showDunesToast(context, '不能与自己发起私聊', kind: DunesToastKind.error);
      return;
    }
    // 不预先创建服务端会话：首次发消息再建，避免对方未收到消息就看到空会话。
    widget.onStartPrivateChat(contact.userId);
  }

  Future<void> _confirmGroupPick() async {
    if (widget.onPickCompleted != null) {
      final ids = _selectedUserIds.where((id) {
        if (id <= 0) return false;
        if (widget.allowSelfInPickMode) return true;
        return id != widget.session.userId;
      }).toSet();
      if (ids.length < widget.minPickCount) {
        showDunesToast(
          context,
          widget.minPickCount <= 1
              ? '请至少选择一位接收人'
              : '群聊至少选择 ${widget.minPickCount} 位同事',
          kind: DunesToastKind.error,
        );
        return;
      }
      final names = <int, String>{
        for (final id in ids)
          id:
              _contactById(id)?.displayName ??
              widget.initialSelectedNames[id] ??
              '成员',
      };
      widget.onPickCompleted!(ids, names);
      return;
    }
    await _createGroupChat();
  }

  Future<void> _createGroupChat() async {
    if (_creating) return;
    final onOpenGroup = widget.onOpenGroupChat;
    if (onOpenGroup == null) {
      showDunesToast(context, '暂不支持创建群聊', kind: DunesToastKind.error);
      return;
    }
    final ids = _selectedUserIds
        .where((id) => id > 0 && id != widget.session.userId)
        .toList(growable: false);
    if (ids.length < widget.minPickCount) {
      showDunesToast(context, '群聊至少选择 ${widget.minPickCount} 位同事', kind: DunesToastKind.error);
      return;
    }
    final previewNames = ids
        .take(3)
        .map((id) => _contactById(id)?.displayName ?? '成员')
        .join('、');
    final more = ids.length > 3 ? ' 等' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认创建群聊'),
        content: Text('将与 $previewNames$more共 ${ids.length} 人创建群聊，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7B5CD8),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _creating = true);
    try {
      final title = ids
          .take(3)
          .map((id) => _contactById(id)?.displayName ?? '成员')
          .join('、');
      final conversation = await _convService.createConversation(
        kind: 'WORKGROUP',
        memberUserIds: ids,
        title: title.isEmpty ? '群聊' : title,
      );
      if (!mounted) return;
      if (conversation == null) throw Exception('创建群聊失败');
      setState(() {
        _groupPickMode = false;
        _selectedUserIds = <int>{};
      });
      onOpenGroup(conversation);
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '创建群聊失败：${friendlyErrorText(e)}',
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: Colors.white,
                child: ContactsHeader(
                  total: _total,
                  onBack: _handleBack,
                  searchOpen: _searchOpen,
                  groupPickMode: _groupPickMode,
                  groupPickTitle: widget.groupPickTitle,
                  groupPickSubtitle: widget.groupPickSubtitle,
                  creating: _creating,
                  onCreateGroup: widget.onOpenGroupChat == null ||
                          widget.onPickCompleted != null
                      ? null
                      : _enterGroupPickMode,
                  onConfirmCreate: _confirmGroupPick,
                  onToggleSearch: () {
                    setState(() {
                      _searchOpen = !_searchOpen;
                      if (!_searchOpen) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      }
                    });
                  },
                ),
              ),
              if (_searchOpen || _groupPickMode)
                ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: DunesColors.text3,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              autofocus: _searchOpen && !_groupPickMode,
                              style: DunesTypography.sans(fontSize: 14),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: '搜索姓名',
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
                ),
              if (_groupPickMode) ...[
                _SelectedMembersBar(
                  selectedUserIds: _selectedUserIds.toList()..sort(),
                  resolveContact: _contactById,
                  avatarService: _convService,
                  onRemove: _removeSelected,
                ),
                _BulkSelectBar(
                  onShowList: _showSelectedMembersSheet,
                  onSelectAll: _selectAllMembers,
                  onClearAll: _clearSelected,
                ),
              ],
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '通讯录加载失败',
              style: DunesTypography.sans(
                fontSize: 15,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final searching = _searchController.text.trim().isNotEmpty;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          OrgSectionLabel(total: _total),
          if (searching) ...[
            if (_searchItems.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    '无匹配联系人',
                    style: TextStyle(color: DunesColors.text3),
                  ),
                ),
              )
            else
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _searchItems.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 66,
                          color: Color(0xFFF0F1F3),
                        ),
                      ContactRowTile(
                        contact: _searchItems[i],
                        currentUserId: widget.session.userId,
                        showOnline:
                            _onlineUsers.contains(_searchItems[i].userId),
                        onOpenProfile: () =>
                            widget.onOpenContact(_searchItems[i]),
                        onMessage: () => _startPrivateChat(_searchItems[i]),
                        avatarService: _convService,
                        pickMode: _groupPickMode,
                        selected:
                            _selectedUserIds.contains(_searchItems[i].userId),
                        onToggleSelect: () => _toggleSelected(_searchItems[i]),
                        allowSelfInPickMode: widget.allowSelfInPickMode,
                      ),
                    ],
                  ],
                ),
              ),
          ] else if (_departments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  '暂无组织数据',
                  style: TextStyle(color: DunesColors.text3),
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _departments.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF0F1F3),
                      ),
                    DeptBlockTile(
                      department: _departments[i],
                      currentUserId: widget.session.userId,
                      onlineUsers: _onlineUsers,
                      onOpenContact: widget.onOpenContact,
                      onMessageContact: _startPrivateChat,
                      avatarService: _convService,
                      pickMode: _groupPickMode,
                      selectedUserIds: _selectedUserIds,
                      onToggleContact: _toggleSelected,
                      allowSelfInPickMode: widget.allowSelfInPickMode,
                    ),
                  ],
                ],
              ),
            ),
          if (!searching && _externalContacts.isNotEmpty) ...[
            ExternalSectionLabel(total: _externalTotal),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _externalContacts.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 66,
                        color: Color(0xFFF0F1F3),
                      ),
                    ContactRowTile(
                      contact: _externalContacts[i],
                      currentUserId: widget.session.userId,
                      showOnline: _onlineUsers.contains(
                        _externalContacts[i].userId,
                      ),
                      onOpenProfile: () =>
                          widget.onOpenContact(_externalContacts[i]),
                      onMessage: () =>
                          _startPrivateChat(_externalContacts[i]),
                      avatarService: _convService,
                      pickMode: _groupPickMode,
                      selected: _selectedUserIds.contains(
                        _externalContacts[i].userId,
                      ),
                      onToggleSelect: () =>
                          _toggleSelected(_externalContacts[i]),
                      allowSelfInPickMode: widget.allowSelfInPickMode,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedMembersSheet extends StatefulWidget {
  const _SelectedMembersSheet({
    required this.selectedUserIds,
    required this.resolveContact,
    required this.avatarService,
    required this.onRemove,
    required this.onDone,
  });

  final Set<int> selectedUserIds;
  final NativeContact? Function(int userId) resolveContact;
  final ConversationService avatarService;
  final ValueChanged<int> onRemove;
  final VoidCallback onDone;

  @override
  State<_SelectedMembersSheet> createState() => _SelectedMembersSheetState();
}

class _SelectedMembersSheetState extends State<_SelectedMembersSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<int> _filteredIds() {
    final ids = widget.selectedUserIds.toList()..sort();
    final q = _keyword.trim().toLowerCase();
    if (q.isEmpty) return ids;
    return ids.where((id) {
      final name = (widget.resolveContact(id)?.displayName ?? '$id')
          .trim()
          .toLowerCase();
      return name.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ids = _filteredIds();
    final total = widget.selectedUserIds.length;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5D7DE),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _keyword.trim().isEmpty
                            ? '已选成员（$total）'
                            : '已选成员（${ids.length}/$total）',
                        style: DunesTypography.sans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onDone,
                      child: Text(
                        '完成',
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: const Color(0xFF7B5CD8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _keyword = v),
                  style: DunesTypography.sans(fontSize: 14),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索已选成员姓名',
                    hintStyle: DunesTypography.sans(
                      fontSize: 14,
                      color: DunesColors.text3,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: Color(0xFF9CA3AF),
                    ),
                    suffixIcon: _keyword.trim().isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _keyword = '');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    filled: true,
                    fillColor: const Color(0xFFF5F6F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE8E9ED)),
              Flexible(
                child: ids.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _keyword.trim().isEmpty ? '暂无已选成员' : '未找到匹配成员',
                          style: DunesTypography.sans(
                            fontSize: 14,
                            color: DunesColors.text3,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 4, 12, 16),
                        itemCount: ids.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          color: Color(0xFFF0F1F5),
                        ),
                        itemBuilder: (context, index) {
                          final id = ids[index];
                          final contact = widget.resolveContact(id);
                          final name = contact?.displayName ?? '$id';
                          final subtitle = [
                            if ((contact?.title ?? '').trim().isNotEmpty)
                              contact!.title!.trim(),
                            if ((contact?.department ?? '').trim().isNotEmpty)
                              contact!.department!.trim(),
                          ].join(' · ');
                          final initial = name.trim().isEmpty
                              ? '?'
                              : String.fromCharCode(name.runes.first);
                          return InkWell(
                            onTap: () {
                              widget.onRemove(id);
                              setState(() {});
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  ImUserAvatar(
                                    initial: initial,
                                    seed: id,
                                    size: 40,
                                    avatarPreset: contact?.avatarPreset,
                                    avatarObjectKey:
                                        contact?.avatarObjectKey,
                                    avatarService: widget.avatarService,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DunesTypography.sans(
                                            fontSize: 15,
                                            color: DunesColors.text,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              color: DunesColors.text3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF9CA3AF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedMembersBar extends StatelessWidget {
  const _SelectedMembersBar({
    required this.selectedUserIds,
    required this.resolveContact,
    required this.avatarService,
    required this.onRemove,
  });

  final List<int> selectedUserIds;
  final NativeContact? Function(int userId) resolveContact;
  final ConversationService avatarService;
  final ValueChanged<int> onRemove;

  String _initial(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE8E9ED))),
      ),
      child: selectedUserIds.isEmpty
          ? Text(
              '请选择群成员',
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final id in selectedUserIds)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => onRemove(id),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ImUserAvatar(
                                  initial: _initial(
                                    resolveContact(id)?.displayName,
                                  ),
                                  seed: id,
                                  size: 40,
                                  avatarPreset:
                                      resolveContact(id)?.avatarPreset,
                                  avatarObjectKey:
                                      resolveContact(id)?.avatarObjectKey,
                                  avatarService: avatarService,
                                ),
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF9CA3AF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 48,
                              child: Text(
                                resolveContact(id)?.displayName ?? '$id',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: DunesTypography.sans(
                                  fontSize: 11,
                                  color: DunesColors.text3,
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
    );
  }
}

class _BulkSelectBar extends StatelessWidget {
  const _BulkSelectBar({
    required this.onShowList,
    required this.onSelectAll,
    required this.onClearAll,
  });

  final VoidCallback onShowList;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;

  ButtonStyle get _outlineStyle => OutlinedButton.styleFrom(
    side: const BorderSide(color: Color(0xFFE0E1E6)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            OutlinedButton(
              onPressed: onSelectAll,
              style: _outlineStyle,
              child: Text(
                '全选',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onClearAll,
              style: _outlineStyle,
              child: Text(
                '清空已选',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onShowList,
              style: _outlineStyle,
              child: Text(
                '列表显示',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
