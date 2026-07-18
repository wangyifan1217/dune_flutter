import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
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
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<int> onStartPrivateChat;
  final ValueChanged<NativeConversation>? onOpenGroupChat;
  final bool initialGroupPickMode;

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

  @override
  void initState() {
    super.initState();
    _groupPickMode = widget.initialGroupPickMode;
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
        _selectedUserIds = <int>{};
      });
    }
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
    if (!contact.enabled ||
        contact.userId <= 0 ||
        contact.userId == widget.session.userId) {
      return;
    }
    setState(() {
      final next = Set<int>.from(_selectedUserIds);
      if (next.contains(contact.userId)) {
        next.remove(contact.userId);
      } else {
        next.add(contact.userId);
      }
      _selectedUserIds = next;
    });
  }

  List<NativeContact> _allSelectableContacts() {
    final all = <NativeContact>[];
    void walk(NativeDepartment dep) {
      all.addAll(
        dep.users.where(
          (c) => c.enabled && c.userId != widget.session.userId,
        ),
      );
      for (final child in dep.children) {
        walk(child);
      }
    }

    for (final dep in _departments) {
      walk(dep);
    }
    for (final c in _externalContacts) {
      if (c.enabled && c.userId != widget.session.userId) {
        all.add(c);
      }
    }
    final seen = <int>{};
    return all.where((c) => seen.add(c.userId)).toList(growable: false);
  }

  NativeContact? _contactById(int userId) {
    for (final c in _searchItems) {
      if (c.userId == userId) return c;
    }
    for (final c in _externalContacts) {
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

  void _selectAllMembers() {
    setState(() {
      _selectedUserIds = _allSelectableContacts()
          .map((c) => c.userId)
          .where((id) => id > 0)
          .toSet();
    });
  }

  void _clearSelected() {
    setState(() => _selectedUserIds = <int>{});
  }

  Future<void> _startPrivateChat(NativeContact contact) async {
    if (contact.userId <= 0) return;
    if (contact.userId == widget.session.userId) {
      showDunesToast(context, '不能与自己发起私聊', kind: DunesToastKind.error);
      return;
    }
    try {
      final convId = await _convService.ensurePrivateConversationForPeer(
        contact.userId,
      );
      if (convId == null || convId <= 0) {
        throw Exception('创建私聊失败');
      }
      widget.onStartPrivateChat(contact.userId);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '创建私聊失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
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
    if (ids.length < 2) {
      showDunesToast(context, '群聊至少选择两位同事', kind: DunesToastKind.error);
      return;
    }
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
                  creating: _creating,
                  onCreateGroup:
                      widget.onOpenGroupChat == null ? null : _enterGroupPickMode,
                  onConfirmCreate: _createGroupChat,
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
                  onRemove: (userId) =>
                      setState(() => _selectedUserIds.remove(userId)),
                ),
                _BulkSelectBar(
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

class _SelectedMembersBar extends StatelessWidget {
  const _SelectedMembersBar({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F8),
        border: Border(bottom: BorderSide(color: Color(0xFFE8E9ED))),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '已选 ${selectedUserIds.length}：',
            style: DunesTypography.sans(
              fontSize: 12,
              color: DunesColors.text3,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (selectedUserIds.isEmpty)
            Text(
              '请选择群成员',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.text3,
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
                    color: DunesColors.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Colors.white70,
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

class _BulkSelectBar extends StatelessWidget {
  const _BulkSelectBar({
    required this.onSelectAll,
    required this.onClearAll,
  });

  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;

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
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E1E6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
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
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0E1E6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                '清空已选',
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
