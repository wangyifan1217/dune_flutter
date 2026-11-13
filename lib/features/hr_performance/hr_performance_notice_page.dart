import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_chat_card.dart';
import 'hr_performance_service.dart';

class HrPerformanceNoticePage extends StatefulWidget {
  const HrPerformanceNoticePage({
    super.key,
    required this.session,
    required this.conversationId,
    this.showBackButton = true,
    this.onBack,
  });

  final AuthSession session;
  final int conversationId;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  State<HrPerformanceNoticePage> createState() =>
      _HrPerformanceNoticePageState();
}

class _HrPerformanceNoticePageState extends State<HrPerformanceNoticePage> {
  late final _service = ConversationService(session: widget.session);
  List<NativeChatMessage> _messages = [];
  bool _busy = false;
  bool _clearing = false;
  bool _hasMore = false;
  String? _error;
  Timer? _timer;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant HrPerformanceNoticePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId == widget.conversationId) return;
    _epoch++;
    _messages = [];
    _hasMore = false;
    _error = null;
    _busy = false;
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool earlier = false}) async {
    if (_busy || _clearing || widget.conversationId <= 0) return;
    final epoch = _epoch;
    setState(() => _busy = true);
    try {
      final page = await _service.fetchMessages(
        widget.conversationId,
        size: 50,
        before: earlier && _messages.isNotEmpty
            ? _messages.map((m) => m.id).reduce((a, b) => a < b ? a : b)
            : null,
      );
      if (!mounted || epoch != _epoch) return;
      final all = {
        for (final m in _messages) m.id: m,
        for (final m in page) m.id: m,
      };
      final rows = all.values.toList()..sort((a, b) => b.id.compareTo(a.id));
      setState(() {
        _messages = rows;
        _error = null;
        if (earlier || _messages.isEmpty || rows.length <= page.length) {
          _hasMore = page.length >= 50;
        }
      });
      await _service.markConversationRead(widget.conversationId);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = friendlyErrorText(e, fallback: '绩效提醒加载失败'));
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing || widget.conversationId <= 0 || _messages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空绩效提醒'),
        content: const Text('只清空这里的提醒记录，不影响已填写的考核表。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '清空',
              style: TextStyle(color: DunesColors.resolve(ctx, DunesColors.coral)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final epoch = ++_epoch;
    setState(() => _clearing = true);
    try {
      await _service.clearConversationHistory(widget.conversationId);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _messages = [];
        _hasMore = false;
        _error = null;
        _busy = false;
        _clearing = false;
      });
      await _load();
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _clearing = false);
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '清空失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = DunesColors.resolve(
      context,
      DunesColors.imSurface,
      role: DunesColorRole.surface,
    );
    final page = DunesColors.resolve(
      context,
      DunesColors.bgApp,
      role: DunesColorRole.surface,
    );
    final border = DunesColors.resolve(
      context,
      DunesColors.borderSoft,
      role: DunesColorRole.border,
    );
    final text = DunesColors.resolve(context, DunesColors.text);
    final text3 = DunesColors.resolve(context, DunesColors.text3);
    return Scaffold(
      backgroundColor: page,
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: surface,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    if (widget.showBackButton)
                      IconButton(
                        tooltip: '返回',
                        onPressed: widget.onBack,
                        icon: Icon(Icons.arrow_back, color: text, size: 20),
                      )
                    else
                      const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hrPerformanceTitle,
                        style: TextStyle(
                          color: text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _messages.isEmpty || _clearing
                          ? null
                          : _clearHistory,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: DunesColors.resolve(
                          context,
                          DunesColors.text2,
                        ),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _busy ? null : () => _load(),
                      icon: Icon(Icons.refresh, color: text3, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _body(surface, border, text, text3)),
          ],
        ),
      ),
    );
  }

  Widget _body(Color surface, Color border, Color text, Color text3) {
    if (widget.conversationId <= 0) {
      return _placeholder(text3, '还没有绩效提醒');
    }
    if (_messages.isEmpty) {
      if (_busy || _clearing) {
        return const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      if (_error != null) {
        return _placeholder(text3, _error!, action: '重试', onAction: _load);
      }
      return _placeholder(text3, '暂无绩效提醒');
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: DunesColors.resolve(context, DunesColors.coral),
                    fontSize: 12,
                  ),
                ),
              ),
            for (final message in _messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _messageCard(message, surface, border, text, text3),
              ),
            if (_hasMore)
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _load(earlier: true),
                  child: Text(_busy ? '加载中…' : '更早消息'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(
    NativeChatMessage message,
    Color surface,
    Color border,
    Color text,
    Color text3,
  ) {
    final payload = message.payload;
    if (payload != null && isHrPerformancePayload(payload)) {
      return HrPerformanceChatCard(
        payload: payload,
        session: widget.session,
        caption: _timeLabel(message.createdAt),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.bodyText,
            style: TextStyle(color: text, fontSize: 13, height: 1.45),
          ),
          if (message.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _timeLabel(message.createdAt),
              style: TextStyle(color: text3, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _placeholder(
    Color text3,
    String label, {
    String? action,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 28, color: text3),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: text3, fontSize: 13)),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final now = DateTime.now();
    final hm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return hm;
    if (local.year == now.year) return '${local.month}/${local.day} $hm';
    return '${local.year}/${local.month}/${local.day} $hm';
  }
}
