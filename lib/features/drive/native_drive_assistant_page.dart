import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_type_icon.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'drive_chat_event.dart';

class NativeDriveAssistantPage extends StatefulWidget {
  const NativeDriveAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    required this.onOpenItem,
    this.showBackButton = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final ValueChanged<int> onOpenItem;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeDriveAssistantPage> createState() =>
      _NativeDriveAssistantPageState();
}

class _NativeDriveAssistantPageState extends State<NativeDriveAssistantPage> {
  late final ConversationService _service = ConversationService(
    session: widget.session,
  );
  List<NativeChatMessage> _messages = const [];
  bool _loading = true;
  bool _clearing = false;
  String? _error;
  int _conversationId = 0;
  StreamSubscription<ConversationRealtimeEvent>? _realtimeSubscription;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _realtimeSubscription = realtime.events.listen(_onRealtime);
    _load();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _reloadDebounce?.cancel();
    _service.close();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var id = widget.conversationHint.id;
      if (id <= 0) {
        id = (await _service.ensureDriveAssistantSession()).id;
      }
      if (id <= 0) throw Exception('企业微盘会话无效');
      _conversationId = id;
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(id),
      );
      final messages = await _service.fetchMessages(id);
      await _service.markConversationRead(id);
      widget.onConversationRead?.call(id);
      if (!mounted) return;
      setState(() => _messages = messages);
    } catch (e) {
      if (mounted && !silent) setState(() => _error = '$e');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (_conversationId <= 0 || event.conversationId != _conversationId) return;
    if (event.type != 'message' && event.type != 'conversation_updated') {
      return;
    }
    unawaited(_service.markConversationRead(_conversationId));
    widget.onConversationRead?.call(_conversationId);
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_load(silent: true));
    });
  }

  Future<void> _confirmClearHistory() async {
    if (_clearing || _conversationId <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空记录？'),
        content: const Text('将清空企业微盘的通知记录，仅对你不可见，不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC44949),
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _service.clearConversationHistory(_conversationId);
      if (!mounted) return;
      setState(() {
        _messages = const [];
        _error = null;
      });
      showDunesToast(context, '已清空记录');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '企业微盘',
              subtitle: _loading ? '加载中…' : '只读通知',
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
              leadingAvatar: const DriveAssistantAvatar(size: 45),
              actions: [
                IconButton(
                  tooltip: '清空记录',
                  onPressed:
                      (_clearing ||
                          _loading ||
                          _conversationId <= 0 ||
                          _messages.isEmpty)
                      ? null
                      : _confirmClearHistory,
                  icon: _clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 22),
                ),
              ],
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _load, child: Text('重试：$_error')),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '共享空间中的文件变化会在这里提醒你',
          style: TextStyle(color: DunesColors.text3),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final event = DriveChatEvent.fromPayload(message.payload);
          return ChatMessageRow(
            message: message,
            mine: false,
            showSenderMeta: true,
            readLabel: null,
            timeLabel: InboxFormat.formatTime(
              message.createdAt,
              withClock: true,
            ),
            avatar: const DriveAssistantAvatar(size: 45),
            content: event == null
                ? ChatTextBubble(text: message.bodyText, mine: false)
                : _DriveEventCard(
                    event: event,
                    onTap: event.canOpen
                        ? () => widget.onOpenItem(event.itemId)
                        : null,
                  ),
          );
        },
      ),
    );
  }
}

class DriveAssistantAvatar extends StatelessWidget {
  const DriveAssistantAvatar({super.key, this.size = 45});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6),
        borderRadius: BorderRadius.circular(size * .18),
      ),
      child: Icon(Icons.cloud_outlined, color: Colors.white, size: size * .48),
    );
  }
}

class _DriveEventCard extends StatelessWidget {
  const _DriveEventCard({required this.event, this.onTap});

  final DriveChatEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.displayText,
            style: const TextStyle(
              fontSize: 14,
              color: DunesColors.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Opacity(
                opacity: event.deleted ? 0.55 : 1,
                child: ChatFileTypeIcon(fileName: event.fileName, size: 36),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: event.deleted ? DunesColors.text3 : DunesColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                event.deleted ? '已删除' : '查看',
                style: TextStyle(
                  fontSize: 12,
                  color: event.deleted
                      ? DunesColors.text3
                      : const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: card,
      ),
    );
  }
}
