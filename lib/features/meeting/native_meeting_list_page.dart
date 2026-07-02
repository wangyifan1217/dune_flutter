import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import 'native_meeting_models.dart';
import 'native_meeting_service.dart';

class NativeMeetingListPage extends StatefulWidget {
  const NativeMeetingListPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onCreate,
    required this.onOpenDetail,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final ValueChanged<int> onOpenDetail;

  @override
  State<NativeMeetingListPage> createState() => _NativeMeetingListPageState();
}

class _NativeMeetingListPageState extends State<NativeMeetingListPage> {
  late final NativeMeetingService _service = NativeMeetingService(
    session: widget.session,
  );
  final ScrollController _scrollController = ScrollController();
  List<NativeMeetingSummary> _rows = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  static const int _pageSize = 20;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _service.fetchList(page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _page = 0;
        _hasMore = rows.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final rows = await _service.fetchList(page: nextPage, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _rows = <NativeMeetingSummary>[..._rows, ...rows];
        _page = nextPage;
        _hasMore = rows.length >= _pageSize;
      });
    } catch (_) {
      // Keep silent on auto load more to avoid frequent interruptions.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteMeeting(NativeMeetingSummary row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会议纪要'),
        content: Text('确定删除「${row.title.isEmpty ? '未命名会议' : row.title}」吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: DunesColors.coral),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteMeeting(row.meetingId);
      if (!mounted) return;
      setState(() => _rows = _rows.where((e) => e.meetingId != row.meetingId).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '删除失败，请稍后重试'))),
      );
    }
  }

  String _statusLabel(String status) {
    return switch (status.toUpperCase()) {
      'GENERATED' => '已生成',
      'TRANSCRIBING' => '转写中',
      'GENERATING' => '生成中',
      'FAILED' => '失败',
      'DRAFT' => '草稿',
      _ => status.isEmpty ? '未知' : status,
    };
  }

  Color _statusColor(String status) {
    return switch (status.toUpperCase()) {
      'GENERATED' => DunesColors.green,
      'TRANSCRIBING' || 'GENERATING' => DunesColors.amber,
      'FAILED' => DunesColors.coral,
      _ => DunesColors.text3,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onBack),
        title: const Text('会议纪要'),
        actions: [
          IconButton(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建会议',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: widget.onCreate,
        backgroundColor: DunesColors.accent,
        foregroundColor: Colors.white,
        child: const Icon(Icons.mic_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          _buildHeroCard(),
          const SizedBox(height: 24),
          _buildMessageCard(
            icon: Icons.error_outline,
            title: '加载失败',
            message: _error!,
            actionLabel: '重试',
            onAction: () => _load(reset: true),
          ),
        ],
      );
    }

    if (_rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _buildHeroCard(),
          const SizedBox(height: 32),
          _buildMessageCard(
            icon: Icons.history_rounded,
            title: '暂无会议记录',
            message: '点击下方麦克风按钮，上传录音并开始 AI 转写',
            actionLabel: '新建会议',
            onAction: widget.onCreate,
          ),
        ],
      );
    }

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        Text(
          '我的会议 · ${_rows.length} 场',
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 10),
        ..._rows.map(_buildMeetingCard),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (!_hasMore && _rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                '没有更多会议记录了',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2F5D62), Color(0xFF1B3A3F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 会议纪要',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '录音转写 · 智能摘要 · 待办提取',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: DunesColors.accent),
          const SizedBox(height: 12),
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 13,
              color: DunesColors.text2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingCard(NativeMeetingSummary row) {
    final status = _statusLabel(row.status);
    final statusColor = _statusColor(row.status);
    final enabled = row.meetingId > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => widget.onOpenDetail(row.meetingId) : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: DunesColors.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: DunesColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title.isEmpty ? '未命名会议' : row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.displayTime,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: DunesTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (row.asrProgress > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${row.asrProgress}%',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: enabled ? () => _deleteMeeting(row) : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: DunesColors.text3,
                  tooltip: '删除',
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: enabled ? DunesColors.text3 : DunesColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
