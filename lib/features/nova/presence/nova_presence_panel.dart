import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../auth/auth_session.dart';
import 'nova_presence_model.dart';

class NovaPresenceTurn {
  const NovaPresenceTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

const novaPresenceAccent = Color(0xFF7965B2);

class NovaPresencePanel extends StatefulWidget {
  const NovaPresencePanel({
    super.key,
    required this.session,
    required this.pageName,
    required this.onClose,
    required this.onExpand,
    required this.onSend,
    this.turns = const [],
    this.sending = false,
    this.error,
    this.onRetry,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.message,
    this.onOpenTask,
    this.conversationId,
    this.confirmPending = false,
    this.onConfirm,
    this.onCancel,
  });

  final AuthSession session;
  final String pageName;
  final NovaPresenceMessage? message;
  final List<NovaPresenceTurn> turns;
  final bool sending;
  final String? error;
  final VoidCallback onClose;
  final ValueChanged<int?> onExpand;
  final ValueChanged<String> onSend;
  final VoidCallback? onRetry;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;
  final GestureDragEndCallback? onDragEnd;
  final VoidCallback? onOpenTask;
  final int? conversationId;
  final bool confirmPending;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  @override
  State<NovaPresencePanel> createState() => _NovaPresencePanelState();
}

class _NovaPresencePanelState extends State<NovaPresencePanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToEnd();
  }

  @override
  void didUpdateWidget(NovaPresencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turns.length != widget.turns.length ||
        oldWidget.sending != widget.sending) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    final value = text.trim();
    if (widget.sending || value.isEmpty || widget.error != null) return;
    FocusScope.of(context).unfocus();
    _input.clear();
    widget.onSend(value);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF0EDF7) : const Color(0xFF302B3D);
    final muted = dark ? const Color(0xFFB3ACBF) : const Color(0xFF8D859C);
    final surface = dark ? const Color(0xFF24212D) : const Color(0xFFFCFBFE);
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: novaPresenceAccent.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              children: [
                MouseRegion(
                  cursor: widget.onDragUpdate == null
                      ? MouseCursor.defer
                      : SystemMouseCursors.grab,
                  child: GestureDetector(
                    onPanStart: widget.onDragStart,
                    onPanUpdate: widget.onDragUpdate,
                    onPanEnd: widget.onDragEnd,
                    child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 12, 16),
                  child: Row(
                    children: [
                      const NovaPresenceAvatar(size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '小饕',
                              style: TextStyle(
                                color: ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '在你身边 · ${widget.pageName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '打开完整对话',
                        onPressed: widget.sending
                            ? null
                            : () => widget.onExpand(widget.conversationId),
                        icon: Icon(
                          Icons.open_in_full_rounded,
                          size: 17,
                          color: muted,
                        ),
                      ),
                      IconButton(
                        tooltip: '收起小饕',
                        onPressed: widget.onClose,
                        icon: Icon(Icons.close_rounded, size: 20, color: muted),
                      ),
                    ],
                  ),
                    ),
                  ),
                ),
                Divider(height: 1, color: muted.withValues(alpha: 0.12)),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(22),
                    children: [
                      if (widget.turns.isEmpty) ...[
                        Text(
                          widget.message?.eyebrow ?? '不用离开这里',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.message?.task != null
                              ? '这件事，\n我们一起往前推。'
                              : widget.message?.text ?? '我在。\n想一起处理点什么？',
                          style: TextStyle(
                            fontSize: 24,
                            height: 1.5,
                            letterSpacing: -0.6,
                            color: ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (widget.message?.task case final task?)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: novaPresenceAccent.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: novaPresenceAccent.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.radio_button_checked_rounded,
                                    size: 15,
                                    color: novaPresenceAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '我的任务',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${task.progressPct}%',
                                    style: const TextStyle(
                                      color: novaPresenceAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                task.title,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 14,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (task.dueAt case final due?)
                                Text(
                                  '截止 ${due.toLocal().month}月${due.toLocal().day}日',
                                  style: TextStyle(color: muted, fontSize: 11),
                                ),
                              const SizedBox(height: 14),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (task.progressPct / 100).clamp(0, 1),
                                  minHeight: 3,
                                  color: novaPresenceAccent,
                                  backgroundColor: novaPresenceAccent
                                      .withValues(alpha: 0.12),
                                ),
                              ),
                              if (widget.onOpenTask != null) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: widget.onOpenTask,
                                  icon: const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                  ),
                                  iconAlignment: IconAlignment.end,
                                  label: const Text('查看任务'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (widget.turns.isEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _suggestion(
                              widget.message?.task != null
                                  ? '帮我梳理下一步'
                                  : '我想整理一下思路',
                            ),
                            _suggestion('你可以怎么帮我？'),
                          ],
                        ),
                      for (final turn in widget.turns)
                        Align(
                          alignment: turn.fromUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: turn.fromUser
                                  ? novaPresenceAccent.withValues(alpha: 0.10)
                                  : novaPresenceAccent.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: MarkdownBody(
                              data: turn.text,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: ink,
                                  fontSize: 14,
                                  height: 1.7,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (widget.sending)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: novaPresenceAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '让我想一想…',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ],
                          ),
                        ),
                      if (widget.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '暂时没能连接小饕：${widget.error}',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                              TextButton(
                                onPressed: widget.sending
                                    ? null
                                    : widget.onRetry,
                                child: const Text('重新试试'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.confirmPending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: widget.sending ? null : widget.onConfirm,
                          child: const Text('确认执行'),
                        ),
                        TextButton(
                          onPressed: widget.sending ? null : widget.onCancel,
                          child: const Text('取消'),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
                    decoration: BoxDecoration(
                      color: novaPresenceAccent.withValues(
                        alpha: dark ? 0.12 : 0.055,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: novaPresenceAccent.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            enabled: !widget.sending && widget.error == null,
                            minLines: 1,
                            maxLines: 4,
                            style: TextStyle(color: ink, fontSize: 14),
                            textInputAction: TextInputAction.send,
                            onSubmitted: _send,
                            decoration: InputDecoration(
                              hintText: '就在这里，和我说说',
                              hintStyle: TextStyle(color: muted, fontSize: 13),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        IconButton.filled(
                          tooltip: '发送',
                          style: IconButton.styleFrom(
                            backgroundColor: novaPresenceAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: widget.sending || widget.error != null
                              ? null
                              : () => _send(_input.text),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestion(String text) => ActionChip(
    onPressed: widget.sending || widget.error != null
        ? null
        : () => _send(text),
    backgroundColor: Colors.transparent,
    side: BorderSide(color: novaPresenceAccent.withValues(alpha: 0.18)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    label: Text(
      text,
      style: const TextStyle(fontSize: 12, color: novaPresenceAccent),
    ),
  );
}

class NovaPresenceAvatar extends StatelessWidget {
  const NovaPresenceAvatar({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF6F0FF), Color(0xFFEAE7F7), Color(0xFFE8F0FF)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
    ),
    child: Image.asset(
      'assets/images/ai_tab_avatar.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    ),
  );
}
