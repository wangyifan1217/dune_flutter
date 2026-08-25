import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'xrxs_chat_card.dart';
import 'xrxs_service.dart';

/// 临时静态预览开关；正式联调请保持 false。
const bool kXrxsAssistantStaticPreview = false;

List<NativeChatMessage> xrxsAssistantStaticPreviewMessages() {
  final now = DateTime.now();
  NativeChatMessage card({
    required int id,
    required String body,
    required String sid,
    required String title,
    required String subtitle,
    required String statusLabel,
    required String eventType,
    required String roleHint,
    required Duration ago,
  }) {
    return NativeChatMessage(
      id: id,
      senderUserId: 0,
      senderName: '薪人薪事',
      kind: 'TEXT',
      bodyText: body,
      createdAt: now.subtract(ago),
      payload: {
        'type': 'xrxsApprovalCard',
        'xrxsCard': {
          'sid': sid,
          'title': title,
          'subtitle': subtitle,
          'statusLabel': statusLabel,
          'eventType': eventType,
          'roleHint': roleHint,
        },
      },
    );
  }

  return [
    card(
      id: -1,
      body: '你有一条薪人薪事审批待办：测试员工的调岗',
      sid: '597873626267779073',
      title: '测试员工的调岗',
      subtitle: '待你审批',
      statusLabel: '待审批',
      eventType: 'flow_todo',
      roleHint: 'approver',
      ago: const Duration(minutes: 2),
    ),
    card(
      id: -2,
      body: '你有一条薪人薪事审批抄送：张三的请假',
      sid: '597873626267779099',
      title: '张三的请假',
      subtitle: '审批抄送',
      statusLabel: '抄送',
      eventType: 'flow_copy',
      roleHint: 'viewer',
      ago: const Duration(minutes: 18),
    ),
    card(
      id: -3,
      body: '薪人薪事审批已结束：采购申请',
      sid: '597873626267779120',
      title: '采购申请',
      subtitle: '审批已结束',
      statusLabel: '已通过',
      eventType: 'flow_process',
      roleHint: 'viewer',
      ago: const Duration(hours: 2),
    ),
  ];
}

class NativeXrxsAssistantPage extends StatefulWidget {
  const NativeXrxsAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    required this.onOpenHome,
    this.onOpenDetail,
    this.showBackButton = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;

  /// 打开薪人薪事首页（XR1：APP 内嵌 H5 / PC 系统浏览器）。
  final VoidCallback onOpenHome;

  /// 打开审批详情；APP 走内嵌 XR1，PC 可外跳系统浏览器。
  final void Function(String sid, String role)? onOpenDetail;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeXrxsAssistantPage> createState() =>
      _NativeXrxsAssistantPageState();
}

class _NativeXrxsAssistantPageState extends State<NativeXrxsAssistantPage> {
  late final ConversationService _service = ConversationService(
    session: widget.session,
  );
  late final XrxsService _xrxs = XrxsService(widget.session);
  List<NativeChatMessage> _messages = const [];
  bool _loading = true;
  bool _clearing = false;
  bool _opening = false;
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
      if (kXrxsAssistantStaticPreview) {
        if (!mounted) return;
        setState(() {
          _conversationId = widget.conversationHint.id;
          _messages = xrxsAssistantStaticPreviewMessages();
          _loading = false;
          _error = null;
        });
        return;
      }
      var id = widget.conversationHint.id;
      if (id <= 0) {
        id = (await _service.ensureXrxsAssistantSession()).id;
      }
      if (id <= 0) throw Exception('薪人薪事会话无效');
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
    // 自己 mark-read 会推 conversation_updated，不能再 mark-read/reload，否则死循环刷日志。
    if (event.type != 'message') return;
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
        content: const Text('将清空薪人薪事的通知记录，仅对你不可见，不可恢复。'),
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

  Future<void> _openCard(XrxsChatCard card) async {
    if (_opening) return;
    if (!card.canOpenDetail) {
      widget.onOpenHome();
      return;
    }
    final onOpenDetail = widget.onOpenDetail;
    if (onOpenDetail != null) {
      onOpenDetail(card.sid, card.roleHint);
      return;
    }
    // 兜底：无宿主回调时 PC 外跳；APP 仍应尽量走 XR1 内嵌。
    setState(() => _opening = true);
    try {
      final preferPc = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux);
      if (!preferPc) {
        widget.onOpenHome();
        return;
      }
      final login = await _xrxs.fetchPcLoginUrl(
        sid: card.sid,
        role: card.roleHint,
      );
      if (!mounted) return;
      final opened = await _xrxs.openInSystemBrowser(login);
      if (!mounted) return;
      if (!opened) {
        showDunesToast(
          context,
          '无法打开系统浏览器',
          kind: DunesToastKind.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
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
              title: '薪人薪事',
              subtitle: _loading
                  ? '加载中…'
                  : (kXrxsAssistantStaticPreview ? '静态预览' : '审批通知'),
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
              leadingAvatar: const XrxsAssistantAvatar(size: 45),
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
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _opening ? null : widget.onOpenHome,
                    child: const Text('打开薪人薪事'),
                  ),
                ),
              ),
            ),
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
          '薪人薪事审批待办与通知会显示在这里',
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
          final card = XrxsChatCard.fromPayload(message.payload);
          return ChatMessageRow(
            message: message,
            mine: false,
            showSenderMeta: true,
            readLabel: null,
            timeLabel: InboxFormat.formatTime(
              message.createdAt,
              withClock: true,
            ),
            avatar: const XrxsAssistantAvatar(size: 45),
            content: card == null
                ? ChatTextBubble(text: message.bodyText, mine: false)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.bodyText.trim().isNotEmpty) ...[
                        ChatTextBubble(text: message.bodyText, mine: false),
                        const SizedBox(height: 8),
                      ],
                      ChatXrxsCard(
                        card: card,
                        onTap: () => unawaited(_openCard(card)),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class XrxsAssistantAvatar extends StatelessWidget {
  const XrxsAssistantAvatar({super.key, this.size = 45});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E),
        borderRadius: BorderRadius.circular(size * .18),
      ),
      child: Icon(
        Icons.badge_outlined,
        color: Colors.white,
        size: size * .48,
      ),
    );
  }
}
