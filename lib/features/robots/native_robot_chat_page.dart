import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/layout/chat_layout.dart';
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
import 'robot_analyzing_coordinator.dart';
import 'robot_character.dart';
import 'robot_consult_api.dart';
import 'robot_markdown.dart';
import 'robot_models.dart';
import 'robot_service.dart';

/// 通讯里的机器人会话：布局/组件对齐私聊 IM，仅支持文本追问。
class NativeRobotChatPage extends StatefulWidget {
  const NativeRobotChatPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onBack,
    this.onConversationRead,
    this.onOpenConsultList,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;
  /// 跳转 NOVA / 千机对应机器人咨询明细列表。
  final VoidCallback? onOpenConsultList;

  @override
  State<NativeRobotChatPage> createState() => _NativeRobotChatPageState();
}

class _NativeRobotChatPageState extends State<NativeRobotChatPage> {
  late final ConversationService _service;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  final List<NativeChatMessage> _messages = [];
  RobotRole? _role;
  bool _loading = true;
  bool _sending = false;
  bool _waitingReply = false;
  bool _clearing = false;
  bool _awayFromLatest = false;
  String? _error;
  int _tempIdSeq = -1;
  Timer? _rtReloadDebounce;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;

  int get _convId => widget.conversationHint.id;
  String get _robotKey {
    final fromHint = widget.conversationHint.robotKey?.trim() ?? '';
    if (fromHint.isNotEmpty) return fromHint;
    return (widget.conversationHint.businessType ?? '').trim();
  }

  RobotAnalyzingCoordinator get _analyzing => RobotAnalyzingCoordinator.instance;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _analyzing.bindSession(widget.session);
    // 离开再进：先用跨页状态恢复「正在分析」，避免等消息加载前空白。
    _waitingReply = _analyzing.isAnalyzing(_convId);
    _scroll.addListener(_onScrollPosition);
    _loadRole();
    _bootstrap();
    _rtSub = ConversationRealtimeHub.instance
        .of(widget.session)
        .events
        .listen(_onRealtime);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtReloadDebounce?.cancel();
    _scroll.removeListener(_onScrollPosition);
    // active-view 由 Host 心跳统一管理，此处勿 clear，避免与 Host 竞态导致角标误亮。
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    final key = _robotKey;
    if (key.isEmpty) {
      setState(() => _role = RobotCatalog.roleById('r_lighthouse'));
      return;
    }
    try {
      final list = await RobotService(session: widget.session).listRobots();
      final hit = list.where((r) => r.id == key).toList();
      setState(() {
        _role = hit.isNotEmpty ? hit.first : RobotCatalog.roleById(key);
      });
    } catch (_) {
      setState(() => _role = RobotCatalog.roleById(key));
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.autoMarkRead && _convId > 0) {
        await _service.markConversationRead(_convId);
        widget.onConversationRead?.call(_convId);
      }
      await _reloadMessages();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sameMessageFingerprint(List<NativeChatMessage> next) {
    if (next.length != _messages.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].id != _messages[i].id) return false;
      if (next[i].bodyText != _messages[i].bodyText) return false;
      if (next[i].kind != _messages[i].kind) return false;
    }
    return true;
  }

  void _syncAnalyzingFlag(bool waiting, {String? question}) {
    if (waiting) {
      _analyzing.markAnalyzing(
        conversationId: _convId,
        robotKey: _robotKey,
        question: question,
      );
    } else {
      _analyzing.clear(_convId);
    }
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || _convId <= 0) return;
    try {
      await _service.markConversationRead(_convId);
      widget.onConversationRead?.call(_convId);
    } catch (_) {}
  }

  Future<void> _reloadMessages({bool silent = false}) async {
    if (_convId <= 0) return;
    try {
      final page = await _service.fetchMessages(_convId, size: 80);
      if (!mounted) return;
      final pendingLocal = _messages
          .where((m) => m.id < 0)
          .where(
            (local) => !page.any(
              (s) =>
                  s.senderUserId == local.senderUserId &&
                  s.bodyText.trim() == local.bodyText.trim() &&
                  s.kind.toUpperCase() == 'TEXT',
            ),
          )
          .toList();
      final merged = <NativeChatMessage>[...page, ...pendingLocal];
      final started = _analyzing.startedAtFor(_convId);
      final freshReply = RobotAnalyzingCoordinator.hasFreshRobotReply(
        merged,
        after: started,
      );
      final detected = RobotAnalyzingCoordinator.detectWaiting(
        merged,
        widget.session.userId,
      );
      // 跨页分析态优先保留；仅确认「开始后的 ROBOT_REPLY」才结束。
      final nextWaiting = freshReply
          ? false
          : (detected ||
              pendingLocal.isNotEmpty ||
              _analyzing.isAnalyzing(_convId));

      if (silent &&
          _sameMessageFingerprint(page) &&
          nextWaiting == _waitingReply) {
        return;
      }
      final wasWaiting = _waitingReply;
      setState(() {
        _messages
          ..clear()
          ..addAll(merged);
        _waitingReply = nextWaiting;
        _error = null;
      });
      _syncAnalyzingFlag(
        nextWaiting,
        question: pendingLocal.isNotEmpty ? pendingLocal.last.bodyText : null,
      );
      if (freshReply && (wasWaiting || widget.autoMarkRead)) {
        unawaited(_markReadIfViewing());
      }
      if (!_awayFromLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _onScrollPosition());
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = friendlyErrorText(e));
      }
    }
  }

  void _onRealtime(ConversationRealtimeEvent ev) {
    if (ev.conversationId != _convId) return;
    if (ev.type != 'message' && ev.type != 'conversation_updated') return;
    final msg = ev.raw['message'];
    if (msg is Map &&
        (msg['kind'] ?? '').toString().toUpperCase() == 'ROBOT_REPLY') {
      _analyzing.clear(_convId);
      if (mounted) setState(() => _waitingReply = false);
      unawaited(_markReadIfViewing());
    }
    _rtReloadDebounce?.cancel();
    _rtReloadDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_reloadMessages(silent: true));
    });
  }

  void _jumpBottom({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (animate) {
      unawaited(
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scroll.jumpTo(max);
    }
    if (_awayFromLatest && mounted) {
      setState(() => _awayFromLatest = false);
    }
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // 正向列表：接近 maxScrollExtent 即最新消息端。
    final away = (pos.maxScrollExtent - pos.pixels) > 140;
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
  }

  Future<void> _confirmClearHistory() async {
    if (_clearing || _convId <= 0) return;
    final role = _role ?? RobotCatalog.roleById(_robotKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空会话？'),
        content: Text(
          '将清空与「${role.name}」的 IM 聊天记录，仅对你不可见，不可恢复。',
        ),
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
      await _service.clearConversationHistory(_convId);
      _analyzing.clear(_convId);
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _waitingReply = false;
        _awayFromLatest = false;
        _error = null;
      });
      showDunesToast(context, '已清空会话');
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

  void _appendOptimisticQuestion(String text) {
    final temp = NativeChatMessage(
      id: _tempIdSeq--,
      senderUserId: widget.session.userId,
      senderName: '我',
      kind: 'TEXT',
      bodyText: text,
      createdAt: DateTime.now(),
      payload: const <String, dynamic>{'consultPending': true, 'local': true},
    );
    setState(() {
      _messages.add(temp);
      _waitingReply = true;
      _sending = true;
    });
    _syncAnalyzingFlag(true, question: text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
  }

  void _dropOptimisticOnFailure(String text) {
    setState(() {
      _messages.removeWhere(
        (m) =>
            m.id < 0 &&
            m.bodyText.trim() == text.trim() &&
            m.senderUserId == widget.session.userId,
      );
      _waitingReply = RobotAnalyzingCoordinator.detectWaiting(
        _messages,
        widget.session.userId,
      );
      _sending = false;
    });
    _syncAnalyzingFlag(_waitingReply);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final key = _robotKey;
    if (key.isEmpty) {
      showDunesToast(context, '缺少 robotKey');
      return;
    }
    _input.clear();
    _appendOptimisticQuestion(text);
    try {
      await _service.sendRobotMessage(
        robotKey: key,
        text: text,
        conversationId: _convId,
      );
      await _reloadMessages();
      if (widget.autoMarkRead) {
        await _service.markConversationRead(_convId);
        widget.onConversationRead?.call(_convId);
      }
    } catch (e) {
      final msg = '$e';
      final needConsultFallback = msg.contains('请通过机器人') ||
          msg.contains('HTTP 400') ||
          msg.contains('HTTP 501') ||
          msg.contains('HTTP 404');
      if (needConsultFallback) {
        try {
          await RobotConsultApi(session: widget.session).start(
            question: text,
            robotKey: key,
            context: <String, dynamic>{
              'conversationId': _convId,
              'skipUserMessage': false,
              'source': 'im_robot_fallback',
            },
          );
          // 轮询等待 ROBOT_REPLY；问题已乐观展示；离开页面由 Coordinator 续等。
          for (var i = 0; i < 40 && _waitingReply && mounted; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1600));
            if (!mounted) return;
            await _reloadMessages(silent: true);
          }
          if (widget.autoMarkRead) {
            await _service.markConversationRead(_convId);
            widget.onConversationRead?.call(_convId);
          }
          return;
        } catch (e2) {
          _analyzing.clear(_convId);
          if (mounted) {
            _dropOptimisticOnFailure(text);
            showDunesToast(
              context,
              friendlyErrorText(e2),
              kind: DunesToastKind.error,
            );
          }
          return;
        }
      }
      _analyzing.clear(_convId);
      if (mounted) {
        _dropOptimisticOnFailure(text);
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _isMine(NativeChatMessage m) {
    if (m.kind.toUpperCase() == 'ROBOT_REPLY') return false;
    return m.senderUserId == widget.session.userId || m.id < 0;
  }

  @override
  Widget build(BuildContext context) {
    final role = _role ?? RobotCatalog.roleById(_robotKey);
    final title = widget.conversationHint.title.trim().isNotEmpty
        ? widget.conversationHint.title.trim()
        : role.name;
    final subtitle = _waitingReply ? '正在分析…' : '文本追问';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: title,
              subtitle: subtitle,
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
              leadingAvatar: RobotFaceAvatar(
                role: role,
                size: 32,
                animate: _waitingReply,
                busy: _waitingReply,
              ),
              actions: [
                IconButton(
                  tooltip: '清空会话',
                  onPressed: (_clearing || _loading) ? null : _confirmClearHistory,
                  icon: _clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 20),
                  color: DunesColors.text2,
                ),
                if (widget.onOpenConsultList != null)
                  IconButton(
                    tooltip: '咨询明细',
                    onPressed: widget.onOpenConsultList,
                    icon: const Icon(Icons.receipt_long_rounded, size: 20),
                    color: DunesColors.text2,
                  ),
              ],
            ),
            Expanded(child: _buildBody(role)),
            ChatInputBar(
              controller: _input,
              focusNode: _focus,
              voiceMode: false,
              voiceEnabled: false,
              sending: _sending,
              enabled: !_loading,
              hintText: '继续追问…',
              onToggleVoice: () {},
              onSend: _send,
              onPlus: null,
              onEmoji: null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(RobotRole role) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _bootstrap, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty && !_waitingReply) {
      return Center(
        child: Text(
          '向「${role.name}」提问，回复会出现在这里',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }

    final wide = isWideChatLayout(context);
    final itemCount = _messages.length + (_waitingReply ? 1 : 0);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
              _onScrollPosition();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 12, wide ? 16 : 12, 12),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (_waitingReply && index == _messages.length) {
                return KeyedSubtree(
                  key: const ValueKey('robot-analyzing'),
                  child: ChatMessageRow(
                    message: NativeChatMessage(
                      id: -999999,
                      senderUserId: 0,
                      senderName: role.name,
                      kind: 'ROBOT_REPLY',
                      bodyText: '正在分析…',
                      createdAt: DateTime.now(),
                    ),
                    mine: false,
                    showSenderMeta: true,
                    readLabel: null,
                    timeLabel: '',
                    avatar: RobotFaceAvatar(
                      role: role,
                      size: 32,
                      animate: true,
                      busy: true,
                    ),
                    content: _RobotReplyBubble(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: DunesColors.text3.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在分析…',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              height: 1.5,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final m = _messages[index];
              final mine = _isMine(m);
              final isRobot = m.kind.toUpperCase() == 'ROBOT_REPLY' || !mine;
              final timeLabel =
                  InboxFormat.formatTime(m.createdAt, withClock: true);
              return KeyedSubtree(
                key: ValueKey('msg-${m.id}-${m.kind}'),
                child: ChatMessageRow(
                  message: m,
                  mine: mine,
                  showSenderMeta: !mine,
                  readLabel: null,
                  timeLabel: timeLabel,
                  showTimeForMine: mine,
                  avatar: isRobot && !mine
                      ? RobotFaceAvatar(role: role, size: 32, animate: false)
                      : null,
                  content: mine
                      ? ChatTextBubble(text: m.bodyText, mine: true)
                      : _RobotReplyBubble(
                          wide: wide,
                          child: m.bodyText.trim().isEmpty
                              ? Text(
                                  '[空回复]',
                                  style: DunesTypography.sans(
                                    fontSize: 13,
                                    color: DunesColors.text3,
                                  ),
                                )
                              : RepaintBoundary(
                                  child: RobotMarkdown(
                                    markdown: m.bodyText,
                                    selectable: false,
                                  ),
                                ),
                        ),
                ),
              );
            },
          ),
        ),
        if (_awayFromLatest)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _jumpBottom(animate: true),
                  borderRadius: BorderRadius.circular(999),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white,
                      border: Border.all(color: DunesColors.borderSoft),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: DunesColors.accentDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '回到最新',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.accentDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 对方气泡样式对齐 [ChatTextBubble]；宽表靠横向滚动，气泡尽量吃满可用宽度。
class _RobotReplyBubble extends StatelessWidget {
  const _RobotReplyBubble({required this.child, this.wide = false});

  final Widget child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    // 手机：留给头像+边距后尽量宽；宽屏：上限放宽，便于多列表格。
    final maxW = wide
        ? (screenW * 0.55).clamp(420.0, 640.0)
        : (screenW - 72).clamp(260.0, 420.0);
    return Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: DunesColors.bgApp,
        border: Border.all(color: DunesColors.borderSoft),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: child,
    );
  }
}
