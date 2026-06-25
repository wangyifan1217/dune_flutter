import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import 'chat_widgets.dart';
import 'user_avatar_widget.dart';

class NativeChatSearchPage extends StatefulWidget {
  const NativeChatSearchPage({
    super.key,
    required this.session,
    required this.conversationId,
    required this.title,
    required this.onBack,
    required this.onLocateMessage,
  });

  final AuthSession session;
  final int conversationId;
  final String title;
  final VoidCallback onBack;
  final ValueChanged<NativeChatMessage> onLocateMessage;

  @override
  State<NativeChatSearchPage> createState() => _NativeChatSearchPageState();
}

class _SearchListEntry {
  const _SearchListEntry.divider(this.label) : message = null;
  const _SearchListEntry.message(this.message) : label = null;

  final String? label;
  final NativeChatMessage? message;
}

class _NativeChatSearchPageState extends State<NativeChatSearchPage> {
  static const _pageSize = 20;

  late final ConversationService _service;
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _oldestId = 0;
  List<NativeChatMessage> _items = const <NativeChatMessage>[];

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scrollController.addListener(_onScroll);
    _queryController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _search();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      unawaited(_search(append: true));
    }
  }

  int _oldestMessageId(Iterable<NativeChatMessage> items) {
    var oldest = 0;
    for (final m in items) {
      if (m.id <= 0) continue;
      if (oldest == 0 || m.id < oldest) oldest = m.id;
    }
    return oldest;
  }

  Future<void> _search({bool append = false}) async {
    final q = _queryController.text.trim();
    if (append) {
      if (_loadingMore || !_hasMore || _oldestId <= 0) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _oldestId = 0;
        _hasMore = false;
      });
    }
    try {
      final page = await _service.searchMessagePage(
        conversationId: widget.conversationId,
        query: q,
        size: _pageSize,
        before: append && _oldestId > 0 ? _oldestId : null,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _items = _merge(_items, page.items);
        } else {
          _items = page.items;
        }
        _oldestId = _oldestMessageId(_items);
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<NativeChatMessage> _merge(List<NativeChatMessage> a, List<NativeChatMessage> b) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) map[m.id] = m;
    }
    return map.values.toList()..sort((x, y) => y.id.compareTo(x.id));
  }

  String _hitBody(NativeChatMessage m) {
    final kind = m.kind.toUpperCase();
    if (kind == 'IMAGE') return '发送了一张图片';
    if (kind == 'FILE') return m.bodyText.isEmpty ? '发送了一个文件' : m.bodyText;
    if (kind == 'AUDIO') return '发送了一条语音';
    return m.bodyText.isEmpty ? '[${m.kind}]' : m.bodyText;
  }

  List<_SearchListEntry> _buildEntries() {
    final sorted = _items.toList()..sort((a, b) => b.id.compareTo(a.id));
    final entries = <_SearchListEntry>[];
    String? lastDivider;
    for (final m in sorted) {
      final label = InboxFormat.dayDividerLabel(m.createdAt);
      if (label != null && label != lastDivider) {
        entries.add(_SearchListEntry.divider(label));
        lastDivider = label;
      }
      entries.add(_SearchListEntry.message(m));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                  ),
                  Expanded(
                    child: Text(
                      '查找聊天内容',
                      style: DunesTypography.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                ],
              ),
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
                    const Icon(Icons.search, size: 16, color: DunesColors.text3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        onSubmitted: (_) => _search(),
                        style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜本群消息 / 文件 / @mention',
                          hintStyle: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_queryController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _queryController.clear();
                          _search();
                        },
                        child: const Icon(Icons.close, size: 16, color: DunesColors.text3),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: _buildResults(entries)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<_SearchListEntry> entries) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(fontSize: 12, color: DunesColors.text3)));
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(
          _queryController.text.trim().isEmpty ? '暂无历史消息' : '暂无搜索结果',
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: entries.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, index) {
        if (index == entries.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return const SizedBox(height: 24);
        }
        final entry = entries[index];
        if (entry.label != null) {
          return ChatDateDivider(label: entry.label!);
        }
        final m = entry.message!;
        return ChatSearchHitCard(
          senderName: m.senderName,
          body: _hitBody(m),
          timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
          avatar: ImUserAvatar(
            initial: m.senderName.isNotEmpty ? m.senderName.substring(0, 1) : '?',
            seed: m.senderUserId,
            size: 34,
            avatarPreset: m.senderAvatarPreset,
            avatarObjectKey: m.senderAvatarObjectKey,
            avatarService: _service,
          ),
          onTap: () => widget.onLocateMessage(m),
        );
      },
    );
  }
}

/// 与 WebView C12 `noti-card` 命中行对齐。
class ChatSearchHitCard extends StatelessWidget {
  const ChatSearchHitCard({
    super.key,
    required this.senderName,
    required this.body,
    required this.timeLabel,
    required this.onTap,
    this.avatar,
  });

  final String senderName;
  final String body;
  final String timeLabel;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar ??
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: DunesColors.accentSoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.chat_bubble_outline, size: 16, color: DunesColors.accentDeep),
                    ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DunesTypography.sans(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (timeLabel.isNotEmpty)
                            Text(timeLabel, style: DunesTypography.mono(fontSize: 9.5, color: DunesColors.text3)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: body,
                              style: DunesTypography.sans(fontSize: 12.5, color: DunesColors.text2, height: 1.35),
                            ),
                            TextSpan(
                              text: '  → 点击定位',
                              style: DunesTypography.mono(fontSize: 9, color: DunesColors.accentDeep),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
