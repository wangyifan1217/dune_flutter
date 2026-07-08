import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
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
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<int> onStartPrivateChat;

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
  String? _error;
  int _total = 0;
  List<NativeDepartment> _departments = const <NativeDepartment>[];
  List<NativeContact> _searchItems = const <NativeContact>[];
  Set<int> _onlineUsers = <int>{};

  @override
  void initState() {
    super.initState();
    _service = ContactService(session: widget.session);
    _convService = ConversationService(session: widget.session);
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
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchOrgContacts(
        keyword: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _total = data.total;
        _departments = data.departments;
        _searchItems = data.searchItems;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContactsHeader(
                total: _total,
                onBack: widget.onBack,
                searchOpen: _searchOpen,
                onToggleSearch: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                });
              },
              ),
              if (_searchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DunesColors.bgSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search,
                          size: 15,
                          color: DunesColors.text3,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            autofocus: true,
                            style: DunesTypography.sans(fontSize: 13),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '搜索同事 · 姓名 / 部门',
                              hintStyle: DunesTypography.sans(
                                fontSize: 13,
                                color: DunesColors.text3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
        padding: const EdgeInsets.only(bottom: 16),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: _searchItems
                      .map(
                        (c) => ContactRowTile(
                          contact: c,
                          currentUserId: widget.session.userId,
                          showOnline: _onlineUsers.contains(c.userId),
                          onOpenProfile: () => widget.onOpenContact(c),
                          onMessage: () => _startPrivateChat(c),
                          avatarService: _convService,
                        ),
                      )
                      .toList(),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: _departments
                    .map(
                      (dep) => DeptBlockTile(
                        department: dep,
                        currentUserId: widget.session.userId,
                        onlineUsers: _onlineUsers,
                        onOpenContact: widget.onOpenContact,
                        onMessageContact: _startPrivateChat,
                        avatarService: _convService,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
