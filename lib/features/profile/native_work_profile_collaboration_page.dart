import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'work_profile_controls.dart';
import 'work_profile_month.dart';

class NativeWorkProfileCollaborationPage extends StatefulWidget {
  const NativeWorkProfileCollaborationPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onOpenConversation,
    this.month,
    this.loadConversations,
    this.onOpenFavorites,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<NativeConversation> onOpenConversation;
  final DateTime? month;
  final Future<List<NativeConversation>> Function()? loadConversations;
  final VoidCallback? onOpenFavorites;

  @override
  State<NativeWorkProfileCollaborationPage> createState() =>
      _NativeWorkProfileCollaborationPageState();
}

class _NativeWorkProfileCollaborationPageState
    extends State<NativeWorkProfileCollaborationPage> {
  List<NativeConversation> _conversations = const [];
  bool _loading = true;
  bool _failed = false;
  ConversationService? _service;
  String _filter = 'all';
  String _department = '';

  @override
  void initState() {
    super.initState();
    if (widget.loadConversations == null) {
      _service = ConversationService(session: widget.session);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _service?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = widget.loadConversations != null
          ? await widget.loadConversations!()
          : await _service!.fetchConversations();
      final month = widget.month;
      final visible =
          rows
              .where(
                (item) =>
                    item.isListedInInbox &&
                    (item.kind == 'PRIVATE' || item.isGroup) &&
                    (month == null ||
                        isSameWorkProfileMonth(item.updatedAt, month)),
              )
              .toList(growable: false)
            ..sort((a, b) => b.sortTimestamp.compareTo(a.sortTimestamp));
      if (!mounted) return;
      setState(() {
        _conversations = visible;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final privateCount = _conversations
        .where((item) => item.kind == 'PRIVATE')
        .length;
    final groupCount = _conversations.where((item) => item.isGroup).length;
    final unreadCount = _conversations.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    final departmentCount = _conversations
        .where((item) => item.kind == 'PRIVATE')
        .map((item) => (item.peerDepartment ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .length;
    final departments =
        _conversations
            .where((item) => item.kind == 'PRIVATE')
            .map((item) => (item.peerDepartment ?? '').trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final visible = _conversations
        .where((item) {
          final matchesType = switch (_filter) {
            'private' => item.kind == 'PRIVATE',
            'group' => item.isGroup,
            'unread' => item.unreadCount > 0,
            'mention' => item.hasUnreadMention || item.hasUnreadAtAll,
            'pinned' => item.pinned,
            _ => true,
          };
          final matchesDepartment =
              _department.isEmpty ||
              (item.peerDepartment ?? '').trim() == _department;
          return matchesType && matchesDepartment;
        })
        .toList(growable: false);

    return Material(
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: widget.onBack),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _ScopeNotice(month: widget.month),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_failed)
                      _ErrorCard(onRetry: () => unawaited(_load()))
                    else ...[
                      _StatsCard(
                        privateCount: privateCount,
                        groupCount: groupCount,
                        unreadCount: unreadCount,
                        departmentCount: departmentCount,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '最近协作会话',
                        style: DunesTypography.sans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF312249),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '按会话最近更新时间排序，点击可直接进入会话。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF817589),
                        ),
                      ),
                      const SizedBox(height: 12),
                      WorkProfileFilterBar(
                        selected: _filter,
                        items: const [
                          ('all', '全部'),
                          ('private', '私聊'),
                          ('group', '群聊'),
                          ('unread', '未读'),
                          ('mention', '@我'),
                          ('pinned', '置顶'),
                        ],
                        onChanged: (value) => setState(() => _filter = value),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: WorkProfileSelectField(
                              label: '协作部门',
                              value: _department,
                              options: [
                                ('', '全部部门'),
                                for (final item in departments) (item, item),
                              ],
                              onChanged: (value) =>
                                  setState(() => _department = value),
                            ),
                          ),
                          if (widget.onOpenFavorites != null) ...[
                            const SizedBox(width: 10),
                            WorkProfileGhostButton(
                              label: '收藏消息',
                              icon: Icons.star_outline_rounded,
                              onPressed: widget.onOpenFavorites!,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (visible.isEmpty)
                        const _EmptyCard()
                      else
                        for (final item in visible.take(20)) ...[
                          _ConversationCard(
                            conversation: item,
                            onTap: () => widget.onOpenConversation(item),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFAFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFF0))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回工作画像',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xFF4A3866),
          ),
          const SizedBox(width: 2),
          Text(
            '协作沉淀',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeNotice extends StatelessWidget {
  const _ScopeNotice({required this.month});

  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final selected = month == null ? '' : '${month!.year}年${month!.month}月';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: Color(0xFF7651B8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${selected.isEmpty ? '' : '$selected · '}按会话最近活跃时间统计当月协作，不是全量历史联系人。',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Color(0xFF5D536B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.privateCount,
    required this.groupCount,
    required this.unreadCount,
    required this.departmentCount,
  });

  final int privateCount;
  final int groupCount;
  final int unreadCount;
  final int departmentCount;

  @override
  Widget build(BuildContext context) {
    final items = <({String label, int value})>[
      (label: '协作联系人', value: privateCount),
      (label: '群聊', value: groupCount),
      (label: '当前未读', value: unreadCount),
      (label: '涉及部门', value: departmentCount),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            SizedBox(
              width: 104,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF8FC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      '${item.value}',
                      style: DunesTypography.sans(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF62438B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF817589),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation, required this.onTap});

  final NativeConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPrivate = conversation.kind == 'PRIVATE';
    final kindLabel = isPrivate ? '私聊' : '群聊';
    final detail = <String>[
      kindLabel,
      if (isPrivate && (conversation.peerDepartment ?? '').trim().isNotEmpty)
        conversation.peerDepartment!.trim(),
      if (!isPrivate && conversation.memberCount > 0)
        '${conversation.memberCount}人',
    ].join(' · ');
    final preview = conversation.preview.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        key: Key('work-profile-collaboration-${conversation.id}'),
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFE9E2EF)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0E8FA),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isPrivate ? Icons.person_rounded : Icons.groups_rounded,
                  color: const Color(0xFF7651B8),
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF342740),
                            ),
                          ),
                        ),
                        if (conversation.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8E6BBC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview.isEmpty ? detail : '$detail · $preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF817589),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Color(0xFF9A7FB8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Text('协作数据暂时无法加载'),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E2EF)),
      ),
      child: const Center(
        child: Text('暂无协作会话', style: TextStyle(color: Color(0xFF817589))),
      ),
    );
  }
}
