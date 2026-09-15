import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/assistant_transcript_support.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import '../shell/dunes_toast.dart';
import 'kpi_chat_card.dart';

class NativeKpiAssistantPage extends StatefulWidget {
  const NativeKpiAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.navigation,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final DunesNavigationController? navigation;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeKpiAssistantPage> createState() => _NativeKpiAssistantPageState();
}

class _NativeKpiAssistantPageState extends State<NativeKpiAssistantPage> {
  late final ConversationService _service = ConversationService(
    session: widget.session,
  );
  late final WorkProfileKpiService _kpi = WorkProfileKpiService(
    session: widget.session,
  );
  final List<NativeChatMessage> _messages = [];
  final ScrollController _scroll = ScrollController();
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _awayFromLatest = false;
  bool _userScrollActive = false;
  int _latestJumpGen = 0;
  DateTime? _userScrollHoldUntil;
  bool _clearing = false;
  String? _detailMonth;
  String? _ackingMonth;
  int _resolvedConvId = 0;
  String? _error;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtDebounce;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _syncBackInterceptor();
    _scroll.addListener(_onScroll);
    _loadMessages();
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _rtSub = realtime.events.listen(_onRealtime);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _clearBackInterceptor();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeKpiAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (_resolvedConvId <= 0 || event.conversationId != _resolvedConvId) {
      return;
    }
    if (event.type != 'message') return;
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_loadMessages(silent: true));
    });
  }

  bool get _hasInternalBack => _detailMonth != null;

  void _installBackInterceptor() {
    final nav = widget.navigation;
    if (nav == null) return;
    nav.canBackInterceptor = _canHandleInternalBack;
    nav.backInterceptor = _handleInternalBack;
  }

  void _clearBackInterceptor() {
    final nav = widget.navigation;
    if (nav == null) return;
    if (nav.canBackInterceptor == _canHandleInternalBack) {
      nav.canBackInterceptor = null;
    }
    if (nav.backInterceptor == _handleInternalBack) {
      nav.backInterceptor = null;
    }
  }

  void _syncBackInterceptor() {
    if (_hasInternalBack) {
      _installBackInterceptor();
    } else {
      _clearBackInterceptor();
    }
  }

  bool _canHandleInternalBack() => _hasInternalBack;

  bool _handleInternalBack() {
    if (_detailMonth != null) {
      _closeDetail();
      return true;
    }
    return false;
  }

  void _openDetail(String month) {
    final m = month.trim();
    if (m.isEmpty) return;
    setState(() => _detailMonth = m);
    _syncBackInterceptor();
  }

  void _closeDetail() {
    setState(() => _detailMonth = null);
    _syncBackInterceptor();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var id = _convId;
      if (id <= 0) {
        id = (await _service.ensureKpiAssistantSession()).id;
      }
      if (id <= 0) throw Exception('绩效助手会话无效');
      _resolvedConvId = id;
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(id),
      );
      final messages = await _service.fetchMessagePage(id);
      await _markReadIfViewing();
      if (!mounted) return;
      final next = silent
          ? mergeLatestAssistantMessages(
              current: List<NativeChatMessage>.from(_messages),
              latest: messages.items,
            )
          : messages.items;
      if (silent && assistantTranscriptUnchanged(_messages, next)) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(next);
        if (!silent) {
          _hasMore = messages.hasMore;
          _loading = false;
        }
      });
      if (!silent) {
        _scrollToLatestOnEnter();
      } else {
        _jumpBottomIfFollowingLatest();
      }
    } catch (e) {
      if (!silent && mounted) setState(() => _error = '$e');
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || windowsTrayIsWindowInactive()) return;
    final id = _resolvedConvId > 0 ? _resolvedConvId : _convId;
    if (id <= 0) return;
    await _service.markConversationRead(id);
    widget.onConversationRead?.call(id);
  }

  bool get _holdingUserScroll {
    if (_userScrollActive) return true;
    final until = _userScrollHoldUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _cancelPendingLatestJumps() {
    _latestJumpGen++;
  }

  void _noteUserMovedScroll({bool towardOlder = false}) {
    _userScrollActive = true;
    _userScrollHoldUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
    _cancelPendingLatestJumps();
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels <= 24 && !towardOlder) return;
    if (!_awayFromLatest && mounted) {
      setState(() => _awayFromLatest = true);
    } else {
      _awayFromLatest = true;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy.abs() <= 0.5) {
      return;
    }
    _userScrollActive = true;
    _userScrollHoldUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
    _cancelPendingLatestJumps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAwayFromLatest(rebuild: true);
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _syncAwayFromLatest(rebuild: !_holdingUserScroll);
    if (assistantShouldLoadOlder(
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      pos: pos,
      reverse: true,
    )) {
      unawaited(_loadOlder());
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    final dragging =
        (n is ScrollStartNotification && n.dragDetails != null) ||
        (n is ScrollUpdateNotification && n.dragDetails != null);
    final userWheel =
        n is UserScrollNotification && n.direction != ScrollDirection.idle;
    final towardOlder =
        n is ScrollUpdateNotification && (n.scrollDelta ?? 0) > 0;
    if (dragging || userWheel || towardOlder) {
      _noteUserMovedScroll(towardOlder: towardOlder);
    } else if (n is ScrollEndNotification) {
      _userScrollActive = false;
      if (n.depth == 0) _syncAwayFromLatest(rebuild: true);
    }
    return false;
  }

  void _syncAwayFromLatest({required bool rebuild}) {
    if (!_scroll.hasClients) return;
    final away = assistantIsAwayFromLatest(_scroll.position, reverse: true);
    if (away == _awayFromLatest) return;
    _awayFromLatest = away;
    if (rebuild && mounted) setState(() {});
  }

  void _scrollToLatestOnEnter() {
    _awayFromLatest = false;
    final gen = ++_latestJumpGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _latestJumpGen || _holdingUserScroll) return;
      _jumpBottom();
    });
  }

  void _jumpBottomIfFollowingLatest() {
    if (_awayFromLatest || _holdingUserScroll) return;
    final gen = _latestJumpGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          gen != _latestJumpGen ||
          _awayFromLatest ||
          _holdingUserScroll) {
        return;
      }
      _jumpBottom();
    });
  }

  void _jumpBottom({bool animate = false}) {
    if (!_scroll.hasClients) return;
    if (!animate && _holdingUserScroll) return;
    const target = 0.0;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
    if (_awayFromLatest && mounted) {
      setState(() => _awayFromLatest = false);
    } else {
      _awayFromLatest = false;
    }
  }

  int? _findMessageChildIndex(Key key) {
    if (key is ValueKey<String> && key.value == 'ka-load-older') {
      return _loadingOlder ? _messages.length : null;
    }
    if (key is! ValueKey<int>) return null;
    final i = _messages.indexWhere((m) => m.id == key.value);
    if (i < 0) return null;
    return _messages.length - 1 - i;
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    final convId = _resolvedConvId > 0 ? _resolvedConvId : _convId;
    if (convId <= 0) return;
    setState(() => _loadingOlder = true);
    final firstId = _messages.first.id;
    try {
      final page = await _service.fetchMessagePage(convId, before: firstId);
      if (!mounted) return;
      final current = List<NativeChatMessage>.from(_messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(
            mergeOlderAssistantMessages(current: current, older: page.items),
          );
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing) return;
    if (_resolvedConvId <= 0) {
      try {
        _resolvedConvId = (await _service.ensureKpiAssistantSession()).id;
      } catch (_) {}
      if (_resolvedConvId <= 0 || !mounted) {
        if (mounted) showDunesCenterToast(context, '会话未就绪，请稍后再试');
        return;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空通知记录'),
        content: const Text(
          '将清空绩效助手里的历史通知（仅自己不可见），绩效分数不受影响。确定清空吗？',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _service.clearConversationHistory(_resolvedConvId);
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _hasMore = false;
        _clearing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _clearing = false);
        showDunesToast(context, '$e', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _ack(KpiAssistantCardData data) async {
    final month = data.month.trim();
    if (month.isEmpty || _ackingMonth != null) return;
    setState(() => _ackingMonth = month);
    try {
      await _kpi.ackRubricScore(month: month);
      if (!mounted) return;
      showDunesCenterToast(context, '已确认本月绩效');
      await _loadMessages(silent: true);
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '$e', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _ackingMonth = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailMonth = _detailMonth;
    if (detailMonth != null) {
      return NativeWorkProfilePerfPage(
        session: widget.session,
        initialMonth: parseKpiMonth(
          detailMonth,
          kpiDefaultScoreMonth(DateTime.now()),
        ),
        onBack: _closeDetail,
      );
    }

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '绩效助手',
              subtitle: _loading ? '加载中…' : '写分后请在卡片上确认已知悉',
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
              leadingAvatar: const KpiAssistantAvatar(size: 45),
              actions: [
                IconButton(
                  tooltip: '清空通知记录',
                  onPressed: _clearing ? null : _clearHistory,
                  icon: _clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.delete_sweep_outlined,
                          size: 22,
                          color: DunesColors.text2,
                        ),
                ),
              ],
            ),
            Expanded(child: _buildMessages()),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _loadMessages, child: Text('重试：$_error')),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            '考核人发布本月结果后，绩效会发到这里。点卡片可看分项、等级和考核人，并确认已知悉。',
            textAlign: TextAlign.center,
            style: TextStyle(color: DunesColors.text3, height: 1.5),
          ),
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: MediaQuery.sizeOf(context).height,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                findChildIndexCallback: _findMessageChildIndex,
                padding: const EdgeInsets.fromLTRB(12, 28, 12, 18),
                itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_loadingOlder && index == _messages.length) {
                    return const Padding(
                      key: ValueKey<String>('ka-load-older'),
                      padding: EdgeInsets.only(top: 8),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final m = _messages[_messages.length - 1 - index];
                  return _buildNoticeRow(m);
                },
              ),
            ),
          ),
        ),
        if (_awayFromLatest)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: AssistantBackToLatestChip(
              onTap: () => _jumpBottom(animate: true),
            ),
          ),
      ],
    );
  }

  Widget _buildNoticeRow(NativeChatMessage m) {
    final payload = m.payload ?? const <String, dynamic>{};
    final data = KpiAssistantCardData.fromPayload(payload);
    final showCard = data.month.isNotEmpty && data.mainScore > 0;
    return ChatMessageRow(
      key: ValueKey<int>(m.id),
      message: m,
      mine: false,
      showSenderMeta: true,
      readLabel: null,
      timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
      avatar: const KpiAssistantAvatar(size: 45),
      content: showCard
          ? ChatKpiAssistantCard(
              data: data,
              acking: _ackingMonth == data.month,
              onConfirm: data.canConfirm ? () => unawaited(_ack(data)) : null,
              onOpenDetail: () => _openDetail(data.month),
            )
          : ChatTextBubble(
              text: m.bodyText,
              mine: false,
              enableSelection: false,
            ),
    );
  }
}
