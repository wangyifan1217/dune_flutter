import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/group_composite_avatar.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_inbox_cache.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../kb/native_kb_models.dart';
import '../proposal_intake/proposal_intake_models.dart';
import '../tasks/task_models.dart';
import '../xflow/xflow_models.dart';
import 'global_search_facade.dart';
import 'global_search_history.dart';
import 'global_search_models.dart';

class NativeGlobalSearchPage extends StatefulWidget {
  const NativeGlobalSearchPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenContact,
    required this.onOpenConversation,
    required this.onOpenMessage,
    required this.onOpenApproval,
    required this.onOpenProposalIntake,
    required this.onOpenTask,
    required this.onOpenKb,
    required this.onOpenDrive,
    required this.onOpenMeeting,
    required this.onOpenApp,
    required this.onOpenNova,
    this.onOpenContacts,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<NativeConversation> onOpenConversation;
  final ValueChanged<GlobalMessageHit> onOpenMessage;
  final ValueChanged<XflowProposalItem> onOpenApproval;
  final ValueChanged<int> onOpenProposalIntake;
  final ValueChanged<int> onOpenTask;
  final ValueChanged<NativeKbDocument> onOpenKb;
  final ValueChanged<int> onOpenDrive;
  final ValueChanged<int> onOpenMeeting;
  final ValueChanged<GlobalSearchAppTarget> onOpenApp;
  final ValueChanged<String> onOpenNova;
  final VoidCallback? onOpenContacts;

  @override
  State<NativeGlobalSearchPage> createState() => _NativeGlobalSearchPageState();
}

class _NativeGlobalSearchPageState extends State<NativeGlobalSearchPage> {
  late final GlobalSearchFacade _facade;
  late final ConversationService _avatarService;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  GlobalSearchCategory _tab = GlobalSearchCategory.all;
  GlobalSearchSnapshot? _snap;
  List<String> _history = const [];
  String _messageKind = '';
  String _approvalFilter = '';
  bool _searching = false;
  MessageThreadGroup? _thread;
  List<GlobalMessageHit> _threadHits = const [];
  bool _threadLoading = false;
  Map<int, ({String? preset, String? objectKey})> _senderAvatarByUserId =
      const <int, ({String? preset, String? objectKey})>{};

  static const _pageBg = Color(0xFFF6F3FA);
  static const _panelColor = Colors.white;
  static const _line = Color(0xFFEDE7F4);

  static const _tabs = <GlobalSearchCategory>[
    GlobalSearchCategory.all,
    GlobalSearchCategory.contacts,
    GlobalSearchCategory.groups,
    GlobalSearchCategory.messages,
    GlobalSearchCategory.approvals,
    GlobalSearchCategory.tasks,
    GlobalSearchCategory.documents,
    GlobalSearchCategory.meetings,
    GlobalSearchCategory.apps,
  ];

  static const _chips = <(GlobalSearchCategory, String)>[
    (GlobalSearchCategory.messages, '聊天记录'),
    (GlobalSearchCategory.approvals, '审批'),
    (GlobalSearchCategory.tasks, '任务'),
    (GlobalSearchCategory.documents, '文档'),
    (GlobalSearchCategory.meetings, '会议'),
    (GlobalSearchCategory.apps, '应用'),
  ];

  bool get _desktop => isDesktopCommOnly;
  EdgeInsets get _listInsets => EdgeInsets.fromLTRB(
    _desktop ? 20 : 12,
    8,
    _desktop ? 20 : 12,
    _desktop ? 72 : 48,
  );

  @override
  void initState() {
    super.initState();
    _facade = GlobalSearchFacade(session: widget.session);
    _avatarService = ConversationService(session: widget.session);
    unawaited(_loadHistory());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _facade.cancel();
    _avatarService.close();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final rows = await GlobalSearchHistoryStore.load();
    if (mounted) setState(() => _history = rows);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _runSearch(value);
    });
  }

  void _runSearch(String raw, {bool persist = false}) {
    final q = raw.trim();
    if (q.isEmpty) {
      _facade.cancel();
      setState(() {
        _snap = null;
        _searching = false;
        _thread = null;
        _threadHits = const [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _thread = null;
      _threadHits = const [];
    });
    unawaited(
      _facade.search(
        query: q,
        tab: _tab,
        messageKind: _messageKind,
        approvalFilter: _approvalFilter,
        emit: _onSnap,
      ),
    );
    if (persist) {
      unawaited(
        GlobalSearchHistoryStore.add(q).then((rows) {
          if (mounted) setState(() => _history = rows);
        }),
      );
    }
  }

  void _onSnap(GlobalSearchSnapshot snap) {
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _searching = snap.groups.values.any(
        (g) => g.status == GlobalSearchGroupStatus.loading,
      );
    });
  }

  void _selectTab(GlobalSearchCategory tab) {
    if (_tab == tab && _thread == null) return;
    setState(() {
      _tab = tab;
      _thread = null;
      _threadHits = const [];
    });
    final q = _controller.text.trim();
    if (q.isNotEmpty) _runSearch(q);
  }

  void _fillHistory(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _runSearch(query, persist: true);
  }

  Future<void> _removeHistory(String query) async {
    final rows = await GlobalSearchHistoryStore.remove(query);
    if (mounted) setState(() => _history = rows);
  }

  Future<void> _clearHistory() async {
    final rows = await GlobalSearchHistoryStore.clear();
    if (mounted) setState(() => _history = rows);
  }

  void _retry(GlobalSearchCategory category) {
    unawaited(
      _facade.retry(
        category: category,
        query: _controller.text.trim(),
        tab: _tab,
        messageKind: _messageKind,
        approvalFilter: _approvalFilter,
        emit: _onSnap,
      ),
    );
  }

  void _rememberQuery() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    unawaited(
      GlobalSearchHistoryStore.add(q).then((rows) {
        if (mounted) setState(() => _history = rows);
      }),
    );
  }

  void _openHit(GlobalSearchHit hit) {
    HapticFeedback.selectionClick();
    _rememberQuery();
    if (hit.kind == GlobalSearchHitKind.message) {
      final thread = hit.raw;
      if (thread is MessageThreadGroup) {
        if (thread.count <= 1) {
          if (thread.latest.messageId > 0) {
            widget.onOpenMessage(thread.latest);
          } else {
            final conv = _conversationById(thread.conversationId);
            if (conv != null) widget.onOpenConversation(conv);
          }
        } else {
          unawaited(_openThread(thread));
        }
        return;
      }
      final m = hit.raw;
      if (m is GlobalMessageHit) widget.onOpenMessage(m);
      return;
    }
    switch (hit.kind) {
      case GlobalSearchHitKind.contact:
        final c = hit.raw;
        if (c is NativeContact) widget.onOpenContact(c);
      case GlobalSearchHitKind.conversation:
        final c = hit.raw;
        if (c is NativeConversation) widget.onOpenConversation(c);
      case GlobalSearchHitKind.message:
        break;
      case GlobalSearchHitKind.approval:
        final a = hit.raw;
        if (a is XflowProposalItem) widget.onOpenApproval(a);
      case GlobalSearchHitKind.proposalIntake:
        final p = hit.raw;
        if (p is ProposalIntakeRow) {
          widget.onOpenProposalIntake(p.id);
        } else {
          widget.onOpenProposalIntake(int.tryParse(hit.id) ?? 0);
        }
      case GlobalSearchHitKind.task:
        final t = hit.raw;
        if (t is TaskItem) {
          widget.onOpenTask(t.id);
        } else {
          widget.onOpenTask(int.tryParse(hit.id) ?? 0);
        }
      case GlobalSearchHitKind.kbDoc:
        final d = hit.raw;
        if (d is NativeKbDocument) widget.onOpenKb(d);
      case GlobalSearchHitKind.driveItem:
        widget.onOpenDrive(int.tryParse(hit.id) ?? 0);
      case GlobalSearchHitKind.meeting:
        widget.onOpenMeeting(int.tryParse(hit.id) ?? 0);
      case GlobalSearchHitKind.app:
        final a = hit.raw;
        if (a is GlobalSearchAppTarget) widget.onOpenApp(a);
    }
  }

  Future<void> _openThread(MessageThreadGroup thread) async {
    setState(() {
      _thread = thread;
      _threadHits = thread.hits;
      _threadLoading = true;
      _tab = GlobalSearchCategory.messages;
    });
    unawaited(_loadThreadAvatarContext(thread));
    try {
      final more = await _facade.loadThreadMessages(
        conversationId: thread.conversationId,
        query: _controller.text.trim(),
        conversationTitle: thread.title,
        kind: _messageKind,
      );
      if (!mounted || _thread?.conversationId != thread.conversationId) return;
      setState(() {
        _threadHits = more.isEmpty ? thread.hits : more;
        _threadLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _threadLoading = false);
    }
  }

  Future<void> _loadThreadAvatarContext(MessageThreadGroup thread) async {
    try {
      final conversation = await _avatarService.fetchConversation(
        thread.conversationId,
      );
      if (conversation == null) return;
      final avatars = <int, ({String? preset, String? objectKey})>{};
      if (conversation.isPrivate) {
        final peerId = conversation.peerUserId ?? 0;
        if (peerId > 0) {
          final contact = await ContactService(
            session: widget.session,
          ).fetchContact(peerId);
          if (contact != null) {
            avatars[peerId] = (
              preset: contact.avatarPreset ?? conversation.peerAvatarPreset,
              objectKey:
                  contact.avatarObjectKey ?? conversation.peerAvatarObjectKey,
            );
          }
        }
      } else {
        final members = await _avatarService.fetchConversationMembers(
          thread.conversationId,
        );
        avatars.addAll(_avatarService.avatarMapFromMembers(members));
      }
      if (!mounted || _thread?.conversationId != thread.conversationId) return;
      setState(() {
        _senderAvatarByUserId = {..._senderAvatarByUserId, ...avatars};
      });
    } catch (_) {
      // Avatar lookup is best-effort; initials remain as a fallback.
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _controller.text.trim();
    final drilling = q.isEmpty && _tab != GlobalSearchCategory.all;
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _desktop ? 760 : 10000),
            child: Column(
              children: [
                _buildBar(),
                if (q.isNotEmpty || drilling) _buildTabs(),
                if (_snap?.slowHint == true) _buildSlowHint(),
                if ((_snap?.queryHint ?? '').isNotEmpty) _buildQueryHint(),
                Expanded(
                  child: q.isEmpty
                      ? (drilling ? _buildCategoryIdle() : _buildIdle())
                      : (_thread != null ? _buildThread() : _buildResults()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _desktop ? 20 : 12,
        14,
        _desktop ? 12 : 8,
        10,
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: _desktop ? 44 : 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focus.hasFocus
                      ? DunesColors.brandPurple.withValues(alpha: 0.45)
                      : _line,
                ),
                boxShadow: [
                  BoxShadow(
                    color: DunesColors.brandPurple.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: DunesColors.brandPurple.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        setState(() {});
                        _onQueryChanged(v);
                      },
                      onSubmitted: (v) => _runSearch(v, persist: true),
                      style: DunesTypography.sans(
                        fontSize: 15,
                        color: DunesColors.text,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索联系人、群聊、聊天记录与办公事项',
                        hintStyle: DunesTypography.sans(
                          fontSize: 14,
                          color: const Color(0xFFB8B0C4),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    _HoverIcon(
                      icon: Icons.close_rounded,
                      onTap: () {
                        _controller.clear();
                        _runSearch('');
                        _focus.requestFocus();
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: widget.onBack,
            style: TextButton.styleFrom(
              foregroundColor: DunesColors.brandPurple,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(48, 40),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: Text(
              '取消',
              style: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.brandPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: _desktop ? 16 : 10),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          final tab = _tabs[i];
          final on = _tab == tab && _thread == null;
          return _HoverSurface(
            radius: BorderRadius.circular(8),
            onTap: () => _selectTab(tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? DunesColors.brandPurple : Colors.transparent,
                    width: 2.2,
                  ),
                ),
              ),
              child: Text(
                tab.label,
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? DunesColors.brandPurple : DunesColors.text2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlowHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: Text(
        '正在搜索更多结果',
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
      ),
    );
  }

  Widget _buildQueryHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Text(
        _snap!.queryHint,
        style: DunesTypography.sans(
          fontSize: 12,
          color: DunesColors.brandPurple,
        ),
      ),
    );
  }

  Widget _buildIdle() {
    final recents = _facade.recentContacts();
    final apps = _facade.recentApps();
    return ListView(
      padding: _listInsets,
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final chip = _chips[i];
              return _chip(chip.$2, () {
                setState(() => _tab = chip.$1);
                _focus.requestFocus();
              });
            },
          ),
        ),
        const SizedBox(height: 14),
        _HoverSurface(
          radius: BorderRadius.circular(14),
          onTap: () => widget.onOpenNova(_controller.text.trim()),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFFF3ECFB), Color(0xFFFFFFFF)],
              ),
              border: Border.all(color: const Color(0xFFDCCFF0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: DunesColors.brandPurple,
                ),
                const SizedBox(width: 8),
                Text(
                  '智能搜索 · 用自然语言找人或事',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.brandPurple,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('搜索历史', action: '清空', onAction: _clearHistory),
          _panel(
            _history
                .map(
                  (q) => _tile(
                    icon: Icons.history_rounded,
                    title: q,
                    subtitle: '最近搜索',
                    onTap: () => _fillHistory(q),
                    trailing: _HoverIcon(
                      icon: Icons.close_rounded,
                      onTap: () => unawaited(_removeHistory(q)),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('最近联系'),
          _panel(
            recents
                .map(
                  (c) => _tile(
                    icon: Icons.person_outline_rounded,
                    title: c.displayTitle,
                    subtitle: [
                      if ((c.peerDepartment ?? '').isNotEmpty)
                        c.peerDepartment!,
                      if ((c.peerRoleLabel ?? '').isNotEmpty) c.peerRoleLabel!,
                    ].join(' · '),
                    leading: _conversationAvatar(c),
                    onTap: () => widget.onOpenConversation(c),
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (apps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('常用应用'),
          _panel(
            apps
                .map(
                  (hit) => _tile(
                    icon: Icons.apps_rounded,
                    title: hit.title,
                    subtitle: hit.subtitle,
                    onTap: () => _openHit(hit),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryIdle() {
    return ListView(
      padding: _listInsets,
      children: [
        if (_tab == GlobalSearchCategory.messages) _messageFilters(),
        if (_tab == GlobalSearchCategory.approvals) _approvalFilters(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Text(
            '输入关键字搜索${_tab.label}',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_tab == GlobalSearchCategory.all) return _buildAll();
    return _buildCategory(_tab);
  }

  Widget _buildAll() {
    final snap = _snap;
    final order = <GlobalSearchCategory>[
      GlobalSearchCategory.contacts,
      GlobalSearchCategory.groups,
      GlobalSearchCategory.messages,
      GlobalSearchCategory.approvals,
      GlobalSearchCategory.tasks,
      GlobalSearchCategory.documents,
      GlobalSearchCategory.meetings,
      GlobalSearchCategory.apps,
    ];
    if (snap == null) return const SizedBox.shrink();
    final children = <Widget>[];
    var anyReady = false;
    var anyHit = false;
    for (final cat in order) {
      final g = snap.group(cat);
      if (g.status == GlobalSearchGroupStatus.ready) anyReady = true;
      if (g.hasItems) anyHit = true;
      final showEmpty =
          g.status == GlobalSearchGroupStatus.loading ||
          g.status == GlobalSearchGroupStatus.timeout ||
          g.status == GlobalSearchGroupStatus.error;
      if (!g.hasItems && !showEmpty) continue;
      children.add(_groupBlock(g, preview: true));
    }
    if (anyReady &&
        !anyHit &&
        !_searching &&
        snap.group(GlobalSearchCategory.messages).status !=
            GlobalSearchGroupStatus.loading) {
      children.add(_emptyAll());
    }
    return ListView(padding: _listInsets, children: children);
  }

  Widget _buildCategory(GlobalSearchCategory cat) {
    final g = _snap?.group(cat);
    return ListView(
      padding: _listInsets,
      children: [
        if (cat == GlobalSearchCategory.messages) _messageFilters(),
        if (cat == GlobalSearchCategory.approvals) _approvalFilters(),
        if (g != null) _groupBlock(g, preview: false),
        if (g != null &&
            g.status == GlobalSearchGroupStatus.ready &&
            !g.hasItems)
          _emptyCategory(cat),
      ],
    );
  }

  Widget _buildThread() {
    final thread = _thread!;
    final q = _controller.text.trim();
    return ListView(
      padding: _listInsets,
      children: [
        _HoverSurface(
          radius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _thread = null;
            _threadHits = const [];
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 14,
                  color: DunesColors.brandPurple,
                ),
                const SizedBox(width: 6),
                Text(
                  '返回聊天记录',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.brandPurple,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionTitle(
          thread.title,
          action: _threadLoading ? '加载中' : '${_threadHits.length} 条相关',
        ),
        _panel(
          _threadHits
              .map(
                (m) => _tile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: m.senderName.isEmpty ? '消息' : m.senderName,
                  subtitle: m.bodyText,
                  query: q,
                  leading: _messageSenderAvatar(m),
                  trailingText: _formatTime(m.createdAt),
                  onTap: () {
                    _rememberQuery();
                    widget.onOpenMessage(m);
                  },
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _groupBlock(GlobalSearchGroupState g, {required bool preview}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            g.category.label,
            action: g.status == GlobalSearchGroupStatus.loading
                ? '加载中'
                : (g.total > 0 ? '${g.total}' : ''),
          ),
          if (g.status == GlobalSearchGroupStatus.timeout ||
              g.status == GlobalSearchGroupStatus.error)
            _retryRow(g)
          else if (g.status == GlobalSearchGroupStatus.loading && !g.hasItems)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (g.hasItems) ...[
            _panel(
              g.items
                  .map(
                    (hit) => _tile(
                      icon: _iconFor(hit.kind),
                      title: hit.title,
                      subtitle: hit.matchCount > 1
                          ? '${hit.matchCount} 条相关 · ${hit.subtitle}'
                          : hit.subtitle,
                      query: _controller.text.trim(),
                      leading: _hitAvatar(hit),
                      trailingText: hit.matchCount > 1
                          ? '${hit.matchCount} 条相关'
                          : _formatTime(hit.time),
                      badge: hit.matchCount > 1,
                      onTap: () => _openHit(hit),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (preview && g.total > g.items.length)
              _HoverText(
                label: '查看全部 ${g.total} 条',
                color: DunesColors.brandPurple,
                onTap: () => _selectTab(g.category),
              ),
          ],
        ],
      ),
    );
  }

  Widget _retryRow(GlobalSearchGroupState g) {
    return _HoverText(
      label: g.error.isEmpty ? '超时，点击重试' : g.error,
      color: DunesColors.brandPurple,
      onTap: () => _retry(g.category),
    );
  }

  Widget _messageFilters() {
    const kinds = <(String, String)>[
      ('', '全部'),
      ('IMAGE', '图片与视频'),
      ('FILE', '文件'),
      ('LINK', '链接'),
      ('FORWARD', '转发'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kinds.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final item = kinds[i];
            return _chip(item.$2, () {
              setState(() => _messageKind = item.$1);
              _runSearch(_controller.text);
            }, active: _messageKind == item.$1);
          },
        ),
      ),
    );
  }

  Widget _approvalFilters() {
    const filters = <(String, String)>[
      ('', '全部'),
      ('pending', '待我处理'),
      ('mine', '我发起'),
      ('done', '已办'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final item = filters[i];
            return _chip(item.$2, () {
              setState(() => _approvalFilter = item.$1);
              _runSearch(_controller.text);
            }, active: _approvalFilter == item.$1);
          },
        ),
      ),
    );
  }

  Widget _emptyAll() {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        children: [
          Text(
            '没有找到相关结果',
            style: DunesTypography.sans(fontSize: 15, color: DunesColors.text2),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _chip('换个词', () {
                _controller.clear();
                _runSearch('');
                _focus.requestFocus();
              }),
              _chip('去智能搜索', () => widget.onOpenNova(_controller.text.trim())),
              _chip('去通讯录', () => widget.onOpenContacts?.call()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCategory(GlobalSearchCategory cat) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(
        '没有找到${cat.label}',
        textAlign: TextAlign.center,
        style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {bool active = false}) {
    return _HoverSurface(
      radius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? DunesColors.brandPurpleSoft : Colors.white,
          border: Border.all(
            color: active ? DunesColors.brandPurpleLine : _line,
          ),
        ),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? DunesColors.brandPurple : DunesColors.text2,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    String action = '',
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text3,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (action.isNotEmpty)
            onAction == null
                ? Text(
                    action,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  )
                : _HoverText(
                    label: action,
                    color: DunesColors.text3,
                    onTap: onAction,
                  ),
        ],
      ),
    );
  }

  Widget _panel(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6E49C8).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1)
              const Divider(height: 1, thickness: 1, color: _line, indent: 58),
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String query = '',
    String trailingText = '',
    Widget? trailing,
    Widget? leading,
    bool badge = false,
  }) {
    return _HoverSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            leading ?? _letterAvatar(title, icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _highlight(title, query, bold: true),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _highlight(subtitle, query, bold: false),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (trailing == null && trailingText.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: badge
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
                    : EdgeInsets.zero,
                decoration: badge
                    ? BoxDecoration(
                        color: DunesColors.brandPurpleSoft,
                        borderRadius: BorderRadius.circular(999),
                      )
                    : null,
                child: Text(
                  trailingText,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: badge ? FontWeight.w700 : FontWeight.w400,
                    color: badge ? DunesColors.brandPurple : DunesColors.text3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget? _hitAvatar(GlobalSearchHit hit) {
    final raw = hit.raw;
    if (raw is NativeConversation) return _conversationAvatar(raw);
    if (raw is NativeContact) return _contactAvatar(raw);
    if (raw is MessageThreadGroup) {
      return _conversationAvatar(_conversationById(raw.conversationId));
    }
    if (raw is GlobalMessageHit) {
      return _conversationAvatar(_conversationById(raw.conversationId));
    }
    return null;
  }

  Widget _messageSenderAvatar(GlobalMessageHit message) {
    const size = 36.0;
    final name = message.senderName.trim();
    final source = _messageSenderAvatarSource(message);
    return ImUserAvatar(
      initial: _initial(name),
      seed: message.senderUserId > 0 ? message.senderUserId : message.messageId,
      size: size,
      avatarPreset: source.preset,
      avatarObjectKey: source.objectKey,
      avatarUrl: source.url,
      avatarService: _avatarService,
      borderRadius: size * 0.18,
    );
  }

  ({String? preset, String? objectKey, String? url}) _messageSenderAvatarSource(
    GlobalMessageHit message,
  ) {
    if (message.senderAvatarPreset?.trim().isNotEmpty == true ||
        message.senderAvatarObjectKey?.trim().isNotEmpty == true ||
        message.senderAvatarUrl?.trim().isNotEmpty == true) {
      return (
        preset: message.senderAvatarPreset,
        objectKey: message.senderAvatarObjectKey,
        url: message.senderAvatarUrl,
      );
    }
    final loaded = _senderAvatarByUserId[message.senderUserId];
    if (loaded != null &&
        (loaded.preset?.trim().isNotEmpty == true ||
            loaded.objectKey?.trim().isNotEmpty == true)) {
      return (preset: loaded.preset, objectKey: loaded.objectKey, url: null);
    }
    final conversation = _conversationById(message.conversationId);
    if (conversation == null) {
      return (preset: null, objectKey: null, url: null);
    }
    ConversationAvatarMember? member;
    for (final candidate in conversation.avatarMembers) {
      if (candidate.userId == message.senderUserId ||
          (message.senderUserId <= 0 &&
              candidate.displayName.trim() == message.senderName.trim())) {
        member = candidate;
        break;
      }
    }
    if (member != null) {
      return (
        preset: member.avatarPreset,
        objectKey: member.avatarObjectKey,
        url: member.avatarUrl,
      );
    }
    if (conversation.isPrivate &&
        message.senderUserId != widget.session.userId) {
      return (
        preset: conversation.peerAvatarPreset,
        objectKey: conversation.peerAvatarObjectKey,
        url: conversation.peerAvatarUrl,
      );
    }
    return (preset: null, objectKey: null, url: null);
  }

  NativeConversation? _conversationById(int id) {
    if (id <= 0) return null;
    final rows = ConversationInboxCache.instance
        .peek(widget.session.userId)
        ?.conversations;
    if (rows == null) return null;
    for (final c in rows) {
      if (c.id == id) return c;
    }
    return null;
  }

  Widget? _conversationAvatar(NativeConversation? c) {
    if (c == null) return null;
    const size = 36.0;
    if ((c.isGroup || c.isWorkgroupApproval) && c.avatarMembers.isNotEmpty) {
      return GroupCompositeAvatar(
        members: c.avatarMembers,
        size: size,
        avatarService: _avatarService,
      );
    }
    if (c.isPrivate || c.isSelfMemo || c.peerUserId != null) {
      return ImUserAvatar(
        initial: _initial(c.displayTitle),
        seed: c.peerUserId ?? c.id,
        size: size,
        avatarPreset: c.peerAvatarPreset,
        avatarObjectKey: c.peerAvatarObjectKey,
        avatarUrl: c.peerAvatarUrl,
        avatarService: _avatarService,
        borderRadius: size * 0.18,
      );
    }
    return null;
  }

  Widget _contactAvatar(NativeContact c) {
    const size = 36.0;
    return ImUserAvatar(
      initial: _initial(c.displayName),
      seed: c.userId,
      size: size,
      avatarPreset: c.avatarPreset,
      avatarObjectKey: c.avatarObjectKey,
      avatarService: _avatarService,
      borderRadius: size * 0.18,
    );
  }

  String _initial(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : t.substring(0, 1);
  }

  Widget _letterAvatar(String title, IconData icon) {
    final letter = title.trim().isEmpty ? '' : title.trim().substring(0, 1);
    final palette = <Color>[
      const Color(0xFF7B5CD8),
      const Color(0xFF3B6E96),
      const Color(0xFF5D8A4E),
      const Color(0xFFB07A2B),
      const Color(0xFFA05670),
    ];
    final color = palette[title.hashCode.abs() % palette.length];
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: letter.isEmpty
          ? Icon(icon, size: 16, color: color)
          : Text(
              letter,
              style: DunesTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
    );
  }

  Widget _highlight(String text, String query, {required bool bold}) {
    final style = DunesTypography.sans(
      fontSize: bold ? 14 : 12,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      color: bold ? DunesColors.text : DunesColors.text3,
    );
    final q = query.trim();
    if (q.isEmpty) {
      return Text(
        text,
        maxLines: bold ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final idx = text.toLowerCase().indexOf(q.toLowerCase());
    if (idx < 0) {
      return Text(
        text,
        maxLines: bold ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, idx), style: style),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: style.copyWith(color: DunesColors.brandPurple),
          ),
          TextSpan(text: text.substring(idx + q.length), style: style),
        ],
      ),
      maxLines: bold ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  IconData _iconFor(GlobalSearchHitKind kind) {
    return switch (kind) {
      GlobalSearchHitKind.contact => Icons.person_outline,
      GlobalSearchHitKind.conversation => Icons.forum_outlined,
      GlobalSearchHitKind.message => Icons.chat_bubble_outline,
      GlobalSearchHitKind.approval => Icons.fact_check_outlined,
      GlobalSearchHitKind.proposalIntake => Icons.description_outlined,
      GlobalSearchHitKind.task => Icons.check_circle_outline,
      GlobalSearchHitKind.kbDoc => Icons.menu_book_outlined,
      GlobalSearchHitKind.driveItem => Icons.cloud_outlined,
      GlobalSearchHitKind.meeting => Icons.videocam_outlined,
      GlobalSearchHitKind.app => Icons.apps_outlined,
    };
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.month}/${local.day}';
  }
}

class _HoverSurface extends StatefulWidget {
  const _HoverSurface({required this.child, required this.onTap, this.radius});

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? radius;

  @override
  State<_HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<_HoverSurface> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF4EFFB) : Colors.transparent,
            borderRadius: widget.radius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoverText extends StatelessWidget {
  const _HoverText({
    required this.label,
    required this.onTap,
    required this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _HoverSurface(
      radius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _HoverIcon extends StatelessWidget {
  const _HoverIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _HoverSurface(
      radius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: const Color(0xFFB2B2B2)),
      ),
    );
  }
}

/// 全局搜索覆盖层：从下往上展开，底下源页面保持可见。
class SearchSlideLayer extends StatefulWidget {
  const SearchSlideLayer({super.key, required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  State<SearchSlideLayer> createState() => _SearchSlideLayerState();
}

class _SearchSlideLayerState extends State<SearchSlideLayer> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) setState(() => _shown = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SearchSlideLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      if (!widget.open) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() => _shown = widget.open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return AnimatedPositioned(
      duration: Duration(milliseconds: _shown ? 400 : 280),
      curve: _shown ? Curves.easeOutCubic : Curves.easeInCubic,
      left: 0,
      right: 0,
      top: _shown ? 0 : height,
      height: height,
      child: TickerMode(
        enabled: widget.open || _shown,
        child: IgnorePointer(
          ignoring: !widget.open,
          child: ColoredBox(
            color: const Color(0xFFF6F3FA),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
