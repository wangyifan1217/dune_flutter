import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'broadcast_service.dart';

const _broadcastAccent = Color(0xFF7B5CD8);

class NativeWorkbenchBroadcastPage extends StatefulWidget {
  const NativeWorkbenchBroadcastPage({
    super.key,
    required this.session,
  });

  final AuthSession session;

  @override
  State<NativeWorkbenchBroadcastPage> createState() =>
      _NativeWorkbenchBroadcastPageState();
}

class _NativeWorkbenchBroadcastPageState
    extends State<NativeWorkbenchBroadcastPage> {
  late final BroadcastService _service = BroadcastService(
    session: widget.session,
  );
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<BroadcastChannel> _channels = const [];
  List<BroadcastHistoryItem> _history = const [];
  int? _channelId;
  final Set<int> _expandedHistoryIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final channels = await _service.listChannels();
      final nextId = _channelId != null &&
              channels.any((c) => c.id == _channelId)
          ? _channelId
          : (channels.isEmpty ? null : channels.first.id);
      final history = await _service.listHistory(conversationId: nextId);
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _channelId = nextId;
        _history = history;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error);
        _loading = false;
      });
    }
  }

  Future<void> _confirmSend() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      showDunesToast(context, '请输入广播正文', kind: DunesToastKind.error);
      return;
    }
    final channelName = _channels
            .where((c) => c.id == _channelId)
            .map((c) => c.title)
            .firstWhere((title) => title.trim().isNotEmpty, orElse: () => '公司广播');
    final preview = body.length > 120 ? '${body.substring(0, 120)}…' : body;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认发布公司广播？'),
        content: Text('频道：$channelName\n\n正文：$preview\n\n将向全员推送，在线用户即时收到。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认发布'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    try {
      await _service.send(
        bodyText: body,
        conversationId: _channelId,
        title: _titleController.text,
      );
      if (!mounted) return;
      _bodyController.clear();
      showDunesToast(context, '广播已推送');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showDunesToast(
        context,
        '发布失败：${friendlyErrorText(error)}',
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmDelete(BroadcastHistoryItem item) async {
    final preview = item.bodyText.length > 120
        ? '${item.bodyText.substring(0, 120)}…'
        : item.bodyText;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除这条广播？'),
        content: Text('正文：$preview\n\n将从 APP 公司广播列表与历史中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFD92D20))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteMessage(item.id);
      if (!mounted) return;
      showDunesToast(context, '已删除');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showDunesToast(
        context,
        '删除失败：${friendlyErrorText(error)}',
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _channels.isEmpty && _history.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text3)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
        _card(
          title: '发布广播',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_channels.length > 1) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey<int?>(_channelId),
                  initialValue: _channelId,
                  decoration: InputDecoration(
                    labelText: '频道',
                    border: _roundedBorder(),
                    enabledBorder: _roundedBorder(),
                    focusedBorder: _roundedBorder(
                      width: 1.6,
                      color: _broadcastAccent,
                    ),
                    isDense: true,
                  ),
                  items: _channels
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(c.title.isEmpty ? '公司广播' : c.title),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (id) {
                    setState(() => _channelId = id);
                    unawaited(_load());
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  labelText: '显示标题',
                  hintText: '选填，默认「公司广播」',
                  border: _roundedBorder(),
                  enabledBorder: _roundedBorder(),
                  focusedBorder: _roundedBorder(
                    width: 1.6,
                    color: _broadcastAccent,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyController,
                minLines: 4,
                maxLines: 8,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  labelText: '广播正文',
                  hintText: '将出现在 APP 沙丘公告 · 公司广播',
                  border: _roundedBorder(),
                  enabledBorder: _roundedBorder(),
                  focusedBorder: _roundedBorder(
                    width: 1.6,
                    color: _broadcastAccent,
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _confirmSend,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(_sending ? '发布中…' : '发布广播'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _broadcastAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _card(
          title: '推送历史',
          child: _history.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '暂无广播记录',
                      style: TextStyle(color: DunesColors.text3),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < _history.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _historyTile(_history[i]),
                    ],
                  ],
                ),
        ),
        ],
      ),
    );
  }

  Widget _historyTile(BroadcastHistoryItem item) {
    final expanded = _expandedHistoryIds.contains(item.id);
    final long = item.bodyText.trim().length > 80 ||
        item.bodyText.trim().split('\n').length > 3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: long
                  ? () => setState(() {
                        if (expanded) {
                          _expandedHistoryIds.remove(item.id);
                        } else {
                          _expandedHistoryIds.add(item.id);
                        }
                      })
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.bodyText,
                      maxLines: expanded ? null : 3,
                      overflow: expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    if (long) ...[
                      const SizedBox(height: 4),
                      Text(
                        expanded ? '收起' : '展开全部',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _broadcastAccent,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      [
                        InboxFormat.formatTime(item.createdAt, withClock: true),
                        if (item.senderName.trim().isNotEmpty)
                          item.senderName.trim(),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => unawaited(_confirmDelete(item)),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFD92D20)),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _roundedBorder({
    double width = 1,
    Color color = const Color(0xFFD8DCE3),
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
