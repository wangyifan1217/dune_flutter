import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../chat/assistant_transcript_support.dart';
import '../chat/chat_widgets.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../desktop/windows_desktop_tray.dart';
import '../robots/robot_markdown.dart';
import 'reconciliation_shucai_models.dart';
import 'reconciliation_shucai_service.dart';
import 'shucai_report_table.dart';

/// 对账助手：真实 RECONCILIATION_ASSISTANT 会话，保留原名片/评价/确认风格。
class NativeReconciliationAssistantPage extends StatefulWidget {
  const NativeReconciliationAssistantPage({
    super.key,
    required this.onBack,
    required this.session,
    required this.conversationHint,
    this.desktopMode = false,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onConversationRead,
  });

  final VoidCallback onBack;
  final AuthSession session;
  final NativeConversation conversationHint;
  final bool desktopMode;
  final bool showBackButton;
  final bool autoMarkRead;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeReconciliationAssistantPage> createState() =>
      _NativeReconciliationAssistantPageState();
}

class _NativeReconciliationAssistantPageState
    extends State<NativeReconciliationAssistantPage> {
  final TextEditingController _commentController = TextEditingController();
  late final ReconciliationShucaiService _shucai;
  late final ConversationService _convService;
  final List<NativeChatMessage> _messages = [];
  final Map<String, ReconCardStatus> _status = {};
  ShucaiSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  bool _confirming = false;
  bool _showDetails = false;
  bool _awayFromLatest = false;
  bool _loadingOlder = false;
  bool _hasMore = false;
  String _detailCardType = 'TAG2';
  String _detailAsOfDate = '';
  String _tag3Tab = 'energy';
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtDebounce;
  Timer? _enterJumpTimer;
  int _latestJumpGen = 0;
  bool _reloadInFlight = false;
  bool _reloadQueuedSilent = false;
  final ScrollController _scroll = ScrollController();

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _shucai = ReconciliationShucaiService(session: widget.session);
    _convService = ConversationService(session: widget.session);
    _bootstrap();
    _scroll.addListener(_onScrollPosition);
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _rtSub = realtime.events.listen(_onRealtime);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
  }

  void _onSelfAvatarUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    _rtSub?.cancel();
    _rtDebounce?.cancel();
    _enterJumpTimer?.cancel();
    _scroll.removeListener(_onScrollPosition);
    _scroll.dispose();
    _commentController.dispose();
    _shucai.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeReconciliationAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_convId <= 0) {
        throw Exception('暂无对账推送');
      }
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(_convId),
      );
      await _markReadIfViewing();
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToLatestOnEnter();
    }
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || windowsTrayIsWindowInactive()) return;
    if (_convId <= 0) return;
    await _convService.markConversationRead(_convId);
    widget.onConversationRead?.call(_convId);
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (event.conversationId != _convId) return;
    // 已读上报会回推 conversation_updated。若据此整页刷新+跳底，
    // 会和 mark-read 形成循环，上滑会被反复拽回底部。
    if (event.type != 'message') return;
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_reload(silent: true));
    });
  }

  Future<void> _hydrateStatus(List<NativeChatMessage> list) async {
    final dates = <String>{};
    for (final msg in list) {
      final card = _cardFromMessage(msg);
      if (card != null && card.asOfDate.isNotEmpty) dates.add(card.asOfDate);
    }
    final statusMap = <String, ReconCardStatus>{};
    for (final date in dates) {
      try {
        final status = await _shucai.fetchStatus(asOfDate: date);
        for (final card in status.cards) {
          statusMap[_statusKey(card.cardType, card.asOfDate)] = card;
        }
      } catch (_) {}
    }
    if (!mounted || _statusMapsEqual(_status, statusMap)) return;
    setState(() {
      _status
        ..clear()
        ..addAll(statusMap);
    });
  }

  bool _statusMapsEqual(
    Map<String, ReconCardStatus> a,
    Map<String, ReconCardStatus> b,
  ) {
    if (identical(a, b) || (a.isEmpty && b.isEmpty)) return true;
    if (a.length != b.length) return false;
    for (final e in b.entries) {
      final cur = a[e.key];
      if (cur == null) return false;
      if (cur.confirmedCount != e.value.confirmedCount ||
          cur.canConfirm != e.value.canConfirm ||
          cur.confirmed != e.value.confirmed ||
          cur.waitingReason != e.value.waitingReason ||
          (cur.mine?.comment ?? '') != (e.value.mine?.comment ?? '')) {
        return false;
      }
    }
    return true;
  }

  bool _sameMessageIds(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _reload({bool silent = false}) async {
    if (_reloadInFlight) {
      if (silent) _reloadQueuedSilent = true;
      return;
    }
    _reloadInFlight = true;
    try {
      final page = await _convService.fetchMessagePage(_convId, size: 30);
      if (!mounted) return;
      final prevLastId = _messages.isEmpty ? 0 : _messages.last.id;
      final next = silent
          ? mergeLatestAssistantMessages(
              current: List<NativeChatMessage>.from(_messages),
              latest: page.items,
            )
          : page.items;
      final messagesChanged = !_sameMessageIds(_messages, next);
      if (messagesChanged) {
        setState(() {
          _messages
            ..clear()
            ..addAll(next);
          if (!silent) _hasMore = page.hasMore;
          if (!silent) _error = null;
        });
      } else if (!silent) {
        setState(() {
          _hasMore = page.hasMore;
          _error = null;
        });
      }
      await _hydrateStatus(_messages);
      if (!mounted) return;
      final current = _currentStatus;
      if (current?.mine != null &&
          _commentController.text.trim().isEmpty &&
          current!.mine!.comment.isNotEmpty) {
        _commentController.text = current.mine!.comment;
      }
      final nextLastId = _messages.isEmpty ? 0 : _messages.last.id;
      final grew = nextLastId > prevLastId;
      if (!silent) {
        _scrollToLatestOnEnter();
      } else if (grew) {
        unawaited(_markReadIfViewing());
        _jumpBottomIfStuck();
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = friendlyErrorText(e));
      }
    } finally {
      _reloadInFlight = false;
      if (_reloadQueuedSilent && mounted) {
        _reloadQueuedSilent = false;
        unawaited(_reload(silent: true));
      }
    }
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    if (assistantShouldLoadOlder(
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      pos: _scroll.position,
    )) {
      unawaited(_loadOlder());
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    final wheelUp =
        n is ScrollUpdateNotification && (n.scrollDelta ?? 0) < 0;
    final userDrag =
        (n is ScrollStartNotification && n.dragDetails != null) ||
        (n is ScrollUpdateNotification && n.dragDetails != null) ||
        (n is UserScrollNotification && n.direction != ScrollDirection.idle);
    if (userDrag || wheelUp) {
      _noteUserMovedScroll();
    }
    if (n is ScrollEndNotification) {
      _syncAwayFromLatest();
    }
    return false;
  }

  bool _isNearLatest({double slop = 24}) {
    if (!_scroll.hasClients) return true;
    final pos = _scroll.position;
    return pos.maxScrollExtent - pos.pixels <= slop;
  }

  void _noteUserMovedScroll() {
    _cancelPendingLatestJumps();
    if (_isNearLatest()) return;
    if (!_awayFromLatest && mounted) {
      setState(() => _awayFromLatest = true);
    } else {
      _awayFromLatest = true;
    }
  }

  void _syncAwayFromLatest() {
    if (!_scroll.hasClients) return;
    final away = !_isNearLatest();
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
  }

  void _cancelPendingLatestJumps() {
    _latestJumpGen++;
    _enterJumpTimer?.cancel();
    _enterJumpTimer = null;
  }

  void _scrollToLatestOnEnter() {
    final gen = ++_latestJumpGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _latestJumpGen) return;
      _jumpBottom(force: true);
    });
    _enterJumpTimer?.cancel();
    _enterJumpTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || gen != _latestJumpGen || _awayFromLatest) return;
      _jumpBottom();
    });
  }

  void _jumpBottomIfStuck() {
    if (_awayFromLatest) return;
    final gen = _latestJumpGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _latestJumpGen || _awayFromLatest) return;
      _jumpBottom();
    });
  }

  void _jumpBottom({bool animate = false, bool force = false}) {
    if (!_scroll.hasClients) return;
    if (!force && _awayFromLatest) return;
    final max = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(max);
    }
    if (force && _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty || _convId <= 0) {
      return;
    }
    setState(() => _loadingOlder = true);
    final firstId = _messages.first.id;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final page = await _convService.fetchMessagePage(
        _convId,
        size: 30,
        before: firstId,
      );
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
      await _hydrateStatus(_messages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(
          assistantOlderScrollRestore(
            oldPixels: oldPixels,
            oldMax: oldMax,
            newMax: _scroll.position.maxScrollExtent,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _closeDetails() {
    setState(() => _showDetails = false);
    _scrollToLatestOnEnter();
  }

  String _statusKey(String cardType, String asOfDate) =>
      '${cardType.toUpperCase()}|$asOfDate';

  ReconCardStatus? get _currentStatus =>
      _status[_statusKey(_detailCardType, _detailAsOfDate)];

  _ReconCardPayload? _cardFromMessage(NativeChatMessage msg) {
    final kind = msg.kind.trim().toUpperCase();
    if (kind != 'RECONCILIATION' && kind != 'RECONCILIATION_ASSISTANT') {
      return null;
    }
    final payload = msg.payload ?? const <String, dynamic>{};
    final cardType = (payload['cardType'] ?? '').toString().trim().toUpperCase();
    if (cardType.isEmpty) return null;
    return _ReconCardPayload(
      cardType: cardType,
      asOfDate: (payload['asOfDate'] ?? '').toString().trim(),
      title: (payload['title'] ?? reconCardTitle(cardType)).toString(),
      subtitle: (payload['subtitle'] ?? '').toString(),
      metric: (payload['metric'] ?? '').toString(),
      createdAt: msg.createdAt,
      viewerOnly: payload['viewerOnly'] == true,
    );
  }

  Future<void> _openDetails(_ReconCardPayload card, {bool refresh = false}) async {
    setState(() {
      _detailCardType = card.cardType;
      _detailAsOfDate = card.asOfDate;
      _showDetails = true;
      if (!refresh) _snapshot = null;
      final mine = _status[_statusKey(card.cardType, card.asOfDate)]?.mine;
      _commentController.text = mine?.comment ?? '';
      if (card.cardType == 'TAG3_ENERGY') {
        _tag3Tab = 'energy';
      } else if (card.cardType == 'TAG3_OPERATOR') {
        _tag3Tab = 'operator';
      }
    });
    try {
      final snap = await _shucai.fetch(
        asOfDate: card.asOfDate,
        cardType: card.cardType,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        if (!snap.tag3.containsKey(_tag3Tab) && snap.tag3.isNotEmpty) {
          _tag3Tab = snap.tag3.keys.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorText(e));
    }
  }

  Future<void> _confirm() async {
    final status = _currentStatus;
    final asOf = _detailAsOfDate;
    final card = _detailCardType;
    if (asOf.isEmpty || card.isEmpty || status == null) return;
    if (!status.canConfirm || status.confirmed) return;
    setState(() => _confirming = true);
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _shucai.confirm(
        asOfDate: asOf,
        cardType: card,
        comment: _commentController.text,
      );
      await _reload(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已记录你的对账意见并完成确认'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  bool get _compact => MediaQuery.sizeOf(context).width < 720;

  String get _dateLabel {
    final date = _detailAsOfDate.isNotEmpty
        ? _detailAsOfDate
        : (_snapshot?.asOfDate ?? '');
    if (date.isEmpty) return '每日对账';
    return shucaiDisplayDate(date);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.desktopMode) {
      return _showDetails
          ? _buildDetailScaffold()
          : _buildConversationScaffold();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final isDetail =
            child.key == const ValueKey<String>('reconciliation-detail');
        final begin = isDetail ? const Offset(1, 0) : const Offset(-0.16, 0);
        return SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          _showDetails ? 'reconciliation-detail' : 'reconciliation-chat',
        ),
        child: _showDetails
            ? _buildDetailScaffold()
            : _buildConversationScaffold(),
      ),
    );
  }

  Widget _buildConversationScaffold() {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '对账助手',
              subtitle: '每日对账',
              onBack: widget.onBack,
              leadingAvatar: const _ReconciliationAssistantAvatar(size: 45),
              actions: [
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : () => _reload(),
                  icon: const Icon(Icons.refresh_rounded, size: 21),
                ),
                IconButton(
                  tooltip: '说明',
                  onPressed: _showInfo,
                  icon: const Icon(Icons.help_outline_rounded, size: 21),
                ),
              ],
            ),
            Expanded(child: _buildConversationBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationBody() {
    if (_loading && _messages.isEmpty) {
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
              FilledButton(onPressed: _bootstrap, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '暂无对账推送',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
            children: [
              if (_loadingOlder)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ..._buildConversationItems(),
            ],
          ),
        ),
        if (_awayFromLatest)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: AssistantBackToLatestChip(
              onTap: () => _jumpBottom(animate: true, force: true),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildConversationItems() {
    const cardOrder = ['TAG2', 'TAG3_ENERGY', 'TAG3_OPERATOR'];
    final groups = <String, List<({NativeChatMessage msg, _ReconCardPayload card})>>{};
    final extras = <NativeChatMessage>[];
    for (final msg in _messages) {
      final kind = msg.kind.trim().toUpperCase();
      if (kind == 'RECONCILIATION_REMIND') {
        extras.add(msg);
        continue;
      }
      final card = _cardFromMessage(msg);
      if (card == null) {
        if (msg.bodyText.trim().isNotEmpty) extras.add(msg);
        continue;
      }
      final key = card.asOfDate.isEmpty ? '_' : card.asOfDate;
      groups.putIfAbsent(key, () => []).add((msg: msg, card: card));
    }
    final dates = groups.keys.toList()..sort();
    final remindByDate = <String, NativeChatMessage>{};
    final otherExtras = <NativeChatMessage>[];
    for (final msg in extras) {
      final kind = msg.kind.trim().toUpperCase();
      if (kind != 'RECONCILIATION_REMIND') {
        otherExtras.add(msg);
        continue;
      }
      final date = ((msg.payload ?? const {})['asOfDate'] ?? '').toString();
      final key = date.isEmpty ? '_${msg.id}' : date;
      final prev = remindByDate[key];
      if (prev == null || msg.id > prev.id) {
        remindByDate[key] = msg;
      }
    }
    final out = <Widget>[];
    for (final date in dates) {
      final byType = <String, ({NativeChatMessage msg, _ReconCardPayload card})>{};
      for (final item in groups[date]!) {
        final typeKey = item.card.cardType.toUpperCase();
        final prev = byType[typeKey];
        if (prev == null || item.msg.id > prev.msg.id) {
          byType[typeKey] = item;
        }
      }
      final items = byType.values.toList()
        ..sort((a, b) {
          final ai = cardOrder.indexOf(a.card.cardType);
          final bi = cardOrder.indexOf(b.card.cardType);
          return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
        });
      final first = items.first.msg;
      final timeLabel = _timeLabel(first.createdAt);
      final needsConfirm = items.any((item) {
        final st = _status[_statusKey(item.card.cardType, item.card.asOfDate)];
        if (st != null) return !st.viewerOnly;
        return !item.card.viewerOnly;
      });
      out.add(
        ChatMessageRow(
          key: ValueKey<String>('recon-day-$date'),
          message: first,
          mine: false,
          showSenderMeta: true,
          readLabel: null,
          timeLabel: timeLabel,
          avatar: const _ReconciliationAssistantAvatar(size: 45),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChatTextBubble(
                text: needsConfirm
                    ? '今日对账信息已生成，请核对下面的对账卡片并完成确认。'
                    : '今日对账信息已生成，请查阅下面的对账卡片。',
                mine: false,
                enableSelection: false,
              ),
              for (final item in items) ...[
                const SizedBox(height: 8),
                _ReconciliationMessageCard(
                  title: item.card.title,
                  subtitle: item.card.subtitle.isEmpty
                      ? '${item.card.asOfDate} · 点击查看明细'
                      : item.card.subtitle,
                  metric: item.card.metric.isEmpty
                      ? (_cardViewerOnly(item.card)
                            ? '查看详情'
                            : '查看详情并确认')
                      : item.card.metric,
                  confirmed:
                      _status[_statusKey(
                            item.card.cardType,
                            item.card.asOfDate,
                          )]
                          ?.confirmed ??
                      false,
                  viewerOnly: _cardViewerOnly(item.card),
                  onTap: () => _openDetails(item.card),
                ),
              ],
            ],
          ),
        ),
      );
      out.add(const SizedBox(height: 8));
      out.add(
        Center(
          child: Text(
            '点击名片查看明细与确认状态',
            style: DunesTypography.sans(
              fontSize: 11.5,
              color: DunesColors.text3,
            ),
          ),
        ),
      );
      out.add(const SizedBox(height: 16));
      final remind = remindByDate.remove(date);
      if (remind != null) {
        out.addAll(_buildExtraMessage(remind));
      }
    }
    final leftoverRemindDates = remindByDate.keys.toList()..sort();
    for (final date in leftoverRemindDates) {
      out.addAll(_buildExtraMessage(remindByDate[date]!));
    }
    for (final msg in otherExtras) {
      out.addAll(_buildExtraMessage(msg));
    }
    return out;
  }

  List<Widget> _buildExtraMessage(NativeChatMessage msg) {
    final kind = msg.kind.trim().toUpperCase();
    final timeLabel = _timeLabel(msg.createdAt);
    if (kind == 'RECONCILIATION_REMIND') {
      return [
        ChatMessageRow(
          message: msg,
          mine: false,
          showSenderMeta: true,
          readLabel: null,
          timeLabel: timeLabel,
          avatar: const _ReconciliationAssistantAvatar(size: 45),
          content: _RemindCard(payload: msg.payload ?? const {}),
        ),
        const SizedBox(height: 12),
      ];
    }
    return [
      ChatMessageRow(
        message: msg,
        mine: false,
        showSenderMeta: true,
        readLabel: null,
        timeLabel: timeLabel,
        avatar: const _ReconciliationAssistantAvatar(size: 45),
        content: ChatTextBubble(
          text: msg.bodyText,
          mine: false,
          enableSelection: false,
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  String _timeLabel(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _showInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对账助手'),
        content: const Text(
          '每天由后台推送三种对账名片。固定时间先发给财务和最终人；财务全部确认后再发给业务一层，一层确认后再发给二层。请按权限查阅对应的表。确认按财务 → 业务一层 → 业务二层依次进行。本层只能看到本层和上一层的进度。最终人只查阅不用确认。超时未确认会通知最终人。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailScaffold() {
    final status = _currentStatus;
    final expected = status?.expectedCount ?? 0;
    final confirmed = status?.confirmedCount ?? 0;
    final progress = expected <= 0
        ? (status?.confirmed == true ? 1.0 : 0.0)
        : (confirmed / expected).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        backgroundColor: DunesColors.bgApp,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: '返回对账消息',
          onPressed: _closeDetails,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5B6FC4), Color(0xFF7652B8)],
                ),
              ),
              child: const Icon(
                Icons.sync_alt_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '对账助手',
              style: DunesTypography.sans(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading
                ? null
                : () {
                    final card = _ReconCardPayload(
                      cardType: _detailCardType,
                      asOfDate: _detailAsOfDate,
                      title: reconCardTitle(_detailCardType),
                      subtitle: '',
                      metric: '',
                      createdAt: null,
                    );
                    unawaited(_openDetails(card, refresh: true));
                    unawaited(_reload(silent: true));
                  },
            icon: const Icon(Icons.refresh_rounded, size: 21),
          ),
          IconButton(
            tooltip: '说明',
            onPressed: _showInfo,
            icon: const Icon(Icons.help_outline_rounded, size: 21),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            _buildHeroCard(status),
            const SizedBox(height: 14),
            _buildSectionTitle('本次对账', _dateLabel),
            const SizedBox(height: 8),
            _buildCurrentSummaryCard(),
            const SizedBox(height: 12),
            _buildDetailTables(),
            const SizedBox(height: 18),
            _buildSectionTitle(
              '确认进度',
              expected <= 0
                  ? (status?.viewerOnly == true
                        ? '仅查阅'
                        : (status?.waitingPrevious == true
                              ? (status?.waitingReason ?? '等待上一层')
                              : (status?.confirmed == true ? '已确认' : '待确认')))
                  : '$confirmed/$expected 人已确认',
            ),
            const SizedBox(height: 8),
            _buildProgressCard(progress, expected, confirmed, status),
            const SizedBox(height: 18),
            _buildSectionTitle(
              '本次评价',
              status?.viewerOnly == true ? '全部确认人' : '本层与上一层可见',
            ),
            const SizedBox(height: 8),
            _buildReviewCard(status),
            if (status?.waitingPrevious == true) ...[
              const SizedBox(height: 18),
              _CardSurface(
                child: Text(
                  status?.waitingReason ?? '请等待上一层确认完成后再确认',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text2,
                  ),
                ),
              ),
            ],
            if (status?.canConfirm == true) ...[
              const SizedBox(height: 18),
              _buildCommentCard(status),
            ],
          ],
        ),
      ),
    );
  }

  bool _cardViewerOnly(_ReconCardPayload card) {
    final st = _status[_statusKey(card.cardType, card.asOfDate)];
    if (st != null) return st.viewerOnly;
    return card.viewerOnly;
  }

  Widget _buildHeroCard(ReconCardStatus? status) {
    final viewerOnly = status?.viewerOnly ?? true;
    final confirmed = status?.confirmed ?? false;
    final waiting = status?.waitingPrevious ?? false;
    final subtitle = viewerOnly
        ? '本张对账表供你查阅，无需确认'
        : (confirmed
              ? '你已完成确认'
              : (waiting
                    ? (status?.waitingReason ?? '请等待上一层确认完成')
                    : '请核对本张对账表并留下你的意见'));
    final pillLabel = viewerOnly
        ? '查阅'
        : (confirmed ? '已确认' : (waiting ? '等待中' : '待确认'));
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F5D62), Color(0xFF477E79)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x182F5D62),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reconCardTitle(_detailCardType)} · $_dateLabel',
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(
            label: pillLabel,
            color: confirmed
                ? const Color(0xFFD7F3E1)
                : Colors.white,
            textColor: confirmed
                ? const Color(0xFF267449)
                : DunesColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String trailing) {
    return Row(
      children: [
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DunesColors.text,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: DunesTypography.sans(fontSize: 11.5, color: DunesColors.text3),
        ),
      ],
    );
  }

  Widget _buildCurrentSummaryCard() {
    final snap = _snapshot;
    if (_detailCardType == 'TAG2') {
      return _CardSurface(
        child: _InfoLine(
          label: '标签二',
          value: '${snap?.tag2.detailRowCount ?? 0} 行',
        ),
      );
    }
    if (_detailCardType == 'TAG3_ENERGY') {
      return _CardSurface(
        child: _InfoLine(
          label: '能源明细',
          value: '${snap?.tag3['energy']?.detailRowCount ?? 0} 条',
        ),
      );
    }
    final parts = <String>[];
    for (final tab in ShucaiSnapshot.tag3TabOrder) {
      if (tab == 'energy') continue;
      final report = snap?.tag3[tab];
      if (report == null) continue;
      parts.add('${ShucaiSnapshot.tabLabel(tab)} ${report.detailRowCount}');
    }
    return _CardSurface(
      child: _InfoLine(
        label: '运营商及相关',
        value: parts.isEmpty ? '暂无' : parts.join(' · '),
      ),
    );
  }

  Widget _buildDetailTables() {
    final snap = _snapshot;
    if (snap == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final compact = _compact;
    if (_detailCardType == 'TAG2') {
      return _buildMarkdownOrTable(
        markdown: snap.tag2Markdown,
        report: snap.tag2.withProvinceColumn,
        compact: compact,
      );
    }
    final tabs = [
      for (final tab in ShucaiSnapshot.tag3TabOrder)
        if (snap.tag3.containsKey(tab) ||
            (snap.tag3Markdown[tab] ?? '').trim().isNotEmpty)
          tab,
    ];
    if (tabs.isEmpty) {
      return _CardSurface(
        child: Text(
          '暂无明细',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }
    final currentTab = snap.tag3.containsKey(_tag3Tab) ||
            (snap.tag3Markdown[_tag3Tab] ?? '').trim().isNotEmpty
        ? _tag3Tab
        : tabs.first;
    final current = snap.tag3[currentTab] ??
        const ShucaiReport(columns: [], rows: []);
    final table = _buildMarkdownOrTable(
      markdown: snap.tag3Markdown[currentTab] ?? '',
      report: current,
      compact: compact,
    );
    if (tabs.length == 1) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final tab in tabs) ...[
                _ShucaiTabChip(
                  label:
                      '${ShucaiSnapshot.tabLabel(tab)} ${snap.tag3[tab]?.detailRowCount ?? 0}',
                  selected: currentTab == tab,
                  onTap: () => setState(() => _tag3Tab = tab),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        table,
      ],
    );
  }

  Widget _buildMarkdownOrTable({
    required String markdown,
    required ShucaiReport report,
    required bool compact,
  }) {
    final md = markdown.trim();
    if (md.isNotEmpty) {
      final body = RobotMarkdown(
        markdown: md,
        compact: compact,
        selectable: !widget.desktopMode,
        fitToContent: widget.desktopMode,
      );
      if (widget.desktopMode) {
        return _DesktopMarkdownScroll(child: body);
      }
      return _CardSurface(child: body);
    }
    return ShucaiReportTable(report: report, compact: compact);
  }

  Widget _buildProgressCard(
    double progress,
    int expected,
    int confirmed,
    ReconCardStatus? status,
  ) {
    final remain = (expected - confirmed).clamp(0, expected);
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '参与人确认状态',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: DunesTypography.mono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: DunesColors.accentSoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                DunesColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (status?.layers.isNotEmpty == true) ...[
            Text(
              status!.layers
                  .map(
                    (l) =>
                        '${l.label} ${l.confirmedCount}/${l.expectedCount}',
                  )
                  .join(' · '),
              style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            status?.waitingPrevious == true
                ? (status?.waitingReason ?? '请等待上一层确认完成')
                : expected <= 0
                    ? (status?.viewerOnly == true
                          ? '本张名片无需你确认'
                          : (status?.confirmed == true
                                ? '你已完成本次确认'
                                : '请完成本次确认'))
                    : (remain == 0
                        ? '可见范围内已全部确认'
                        : '还有 $remain 位参与人待确认'),
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ReconCardStatus? status) {
    final others = status?.others ?? const <ReconPerson>[];
    final expected = status?.expected ?? const <ReconPerson>[];
    final ackedIds = {
      for (final p in status?.acks ?? const <ReconPerson>[]) p.userId,
    };
    final pending = expected.where((p) => !ackedIds.contains(p.userId)).toList();
    final expectedById = <int, ReconPerson>{
      for (final p in expected) p.userId: p,
    };
    final entries = <_ReviewEntry>[];
    for (final person in others) {
      final merged = _personWithAvatar(person, expectedById[person.userId]);
      entries.add(
        _ReviewEntry(
          person: merged,
          confirmed: true,
          isSelf: false,
          comment: merged.comment.trim().isEmpty ? '已确认' : merged.comment.trim(),
        ),
      );
    }
    for (final person in pending) {
      if (person.userId == widget.session.userId) continue;
      entries.add(
        _ReviewEntry(
          person: person,
          confirmed: false,
          isSelf: false,
          comment: '尚未确认',
        ),
      );
    }
    final selfSnap = userAvatarRefresh.snapshotFor(widget.session.userId);
    final selfPerson = _personWithAvatar(
      status?.mine ??
          ReconPerson(
            userId: widget.session.userId,
            userName: (widget.session.displayName ?? '').trim(),
            role: status?.myRole ?? '',
          ),
      expectedById[widget.session.userId],
    );
    if (status?.canConfirm == true || status?.waitingPrevious == true) {
      entries.add(
        _ReviewEntry(
          person: selfPerson,
          confirmed: status?.confirmed == true,
          isSelf: true,
          comment: _commentController.text.trim().isEmpty
              ? (status?.waitingPrevious == true
                    ? (status?.waitingReason ?? '等待上一层确认完成')
                    : '等待你填写意见')
              : _commentController.text.trim(),
        ),
      );
    }
    entries.sort((a, b) {
      final layerCmp = reconRoleLayer(a.person.role)
          .compareTo(reconRoleLayer(b.person.role));
      if (layerCmp != 0) return layerCmp;
      if (a.confirmed != b.confirmed) return a.confirmed ? -1 : 1;
      if (a.isSelf != b.isSelf) return a.isSelf ? 1 : -1;
      return a.person.displayName.compareTo(b.person.displayName);
    });
    if (entries.isEmpty) {
      return _CardSurface(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '暂无核对人评价',
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
        ),
      );
    }
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) {
        children.add(
          const Divider(height: 1, indent: 68, color: DunesColors.borderSoft),
        );
      }
      final item = entries[i];
      final merged = item.person;
      children.add(
        _ReviewRow(
          userId: merged.userId,
          initial: item.isSelf ? '我' : _initial(merged.displayName),
          name: item.isSelf ? '我' : merged.displayName,
          role: item.isSelf && status?.myRole.isNotEmpty == true
              ? ReconPerson(
                  userId: widget.session.userId,
                  role: status!.myRole,
                ).roleLabel
              : merged.roleLabel,
          comment: item.comment,
          status: item.confirmed ? '已确认' : '待确认',
          statusColor: item.confirmed ? DunesColors.green : DunesColors.amber,
          avatarColor: item.isSelf
              ? const Color(0xFFD7E8E6)
              : (item.confirmed
                    ? const Color(0xFFE7DFF5)
                    : const Color(0xFFDCEBEA)),
          avatarTextColor: item.isSelf || !item.confirmed
              ? DunesColors.accent
              : DunesColors.brandPurpleDeep,
          avatarPreset: item.isSelf &&
                  (selfSnap?.avatarPreset ?? '').trim().isNotEmpty
              ? selfSnap!.avatarPreset
              : merged.avatarPreset,
          avatarObjectKey: item.isSelf &&
                  (selfSnap?.avatarObjectKey ?? '').trim().isNotEmpty
              ? selfSnap!.avatarObjectKey
              : merged.avatarObjectKey,
          avatarUrl: item.isSelf ? (selfSnap?.avatarUrl ?? '').trim() : '',
          avatarService: _convService,
          isSelf: item.isSelf,
        ),
      );
    }
    return _CardSurface(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }

  String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first);
  }

  ReconPerson _personWithAvatar(ReconPerson person, ReconPerson? extra) {
    if (extra == null) return person;
    return ReconPerson(
      userId: person.userId,
      userName: person.userName.isNotEmpty ? person.userName : extra.userName,
      role: person.role.isNotEmpty ? person.role : extra.role,
      comment: person.comment,
      confirmedAt: person.confirmedAt,
      avatarPreset: person.avatarPreset.isNotEmpty
          ? person.avatarPreset
          : extra.avatarPreset,
      avatarObjectKey: person.avatarObjectKey.isNotEmpty
          ? person.avatarObjectKey
          : extra.avatarObjectKey,
    );
  }

  Widget _buildCommentCard(ReconCardStatus? status) {
    final confirmed = status?.confirmed ?? false;
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的评价',
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '本层与上一层可见',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            enabled: !confirmed,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text),
            decoration: InputDecoration(
              hintText: '输入本次对账意见（可选）',
              hintStyle: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
              filled: true,
              fillColor: DunesColors.bgSoft,
              contentPadding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DunesColors.accentLine),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: confirmed || _confirming ? null : _confirm,
              icon: Icon(
                confirmed ? Icons.check_circle_outline : Icons.check_rounded,
                size: 19,
              ),
              label: Text(
                _confirming
                    ? '提交中…'
                    : (confirmed ? '已确认本次对账' : '确认本次对账'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: DunesColors.accent,
                disabledBackgroundColor: DunesColors.greenSoft,
                disabledForegroundColor: DunesColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewEntry {
  const _ReviewEntry({
    required this.person,
    required this.confirmed,
    required this.isSelf,
    required this.comment,
  });

  final ReconPerson person;
  final bool confirmed;
  final bool isSelf;
  final String comment;
}

class _ReconCardPayload {
  const _ReconCardPayload({
    required this.cardType,
    required this.asOfDate,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.createdAt,
    this.viewerOnly = false,
  });

  final String cardType;
  final String asOfDate;
  final String title;
  final String subtitle;
  final String metric;
  final DateTime? createdAt;
  final bool viewerOnly;
}

class _RemindCard extends StatelessWidget {
  const _RemindCard({required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final asOfDate = (payload['asOfDate'] ?? '').toString();
    final items = payload['items'];
    final lines = <String>[];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final title = reconCardTitle((item['cardType'] ?? '').toString());
        final people = item['unconfirmed'];
        final names = people is List
            ? people.map((e) => e.toString()).join('、')
            : '';
        if (names.isNotEmpty) lines.add('$title：$names');
      }
    }
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '未确认催办${asOfDate.isEmpty ? '' : ' · ${shucaiDisplayDate(asOfDate)}'}',
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lines.isEmpty ? '仍有核对人未确认' : lines.join('\n'),
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2),
          ),
        ],
      ),
    );
  }
}

class _ReconciliationAssistantAvatar extends StatelessWidget {
  const _ReconciliationAssistantAvatar({this.size = 45});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B6FC4), Color(0xFF7652B8)],
        ),
      ),
      child: Icon(
        Icons.sync_alt_rounded,
        color: Colors.white,
        size: size * .44,
      ),
    );
  }
}

class _ReconciliationMessageCard extends StatelessWidget {
  const _ReconciliationMessageCard({
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.confirmed,
    required this.onTap,
    this.viewerOnly = false,
  });

  final String title;
  final String subtitle;
  final String metric;
  final bool confirmed;
  final bool viewerOnly;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3F1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC9DFDA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.compare_arrows_rounded,
                        size: 16,
                        color: DunesColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: DunesTypography.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                          ),
                        ),
                      ),
                      _StatusPill(
                        compact: true,
                        label: viewerOnly
                            ? '查阅'
                            : (confirmed ? '已确认' : '待确认'),
                        color: viewerOnly
                            ? const Color(0xFFE4EEEC)
                            : (confirmed
                                  ? const Color(0xFFD7F3E1)
                                  : const Color(0xFFFFF3DC)),
                        textColor: viewerOnly
                            ? DunesColors.accent
                            : (confirmed
                                  ? const Color(0xFF267449)
                                  : DunesColors.amber),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          metric,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DunesTypography.mono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.green,
                          ),
                        ),
                      ),
                      Text(
                        '查看详情',
                        style: DunesTypography.sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.accent,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: DunesColors.accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShucaiTabChip extends StatelessWidget {
  const _ShucaiTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? DunesColors.accentSoft : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? DunesColors.accentLine : DunesColors.borderSoft,
            ),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? DunesColors.accent : DunesColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// PC：宽 Markdown 表可鼠标拖、滚轮/触控板横向滑，并显示底栏滚动条。
class _DesktopMarkdownScroll extends StatefulWidget {
  const _DesktopMarkdownScroll({required this.child});

  final Widget child;

  @override
  State<_DesktopMarkdownScroll> createState() => _DesktopMarkdownScrollState();
}

class _DesktopMarkdownScrollState extends State<_DesktopMarkdownScroll> {
  final ScrollController _h = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_h.hasClients) return;
    var delta = event.scrollDelta.dx;
    final shift = HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    if (delta == 0 && shift) {
      delta = event.scrollDelta.dy;
    }
    if (delta == 0 || !_h.position.hasContentDimensions) return;
    final next = (_h.offset + delta).clamp(
      _h.position.minScrollExtent,
      _h.position.maxScrollExtent,
    );
    if (next != _h.offset) {
      _h.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CardSurface(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: Scrollbar(
            controller: _h,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              primary: false,
              padding: const EdgeInsets.only(bottom: 10),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.child,
    this.padding = const EdgeInsets.all(15),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.textColor,
    this.compact = false,
  });

  final String label;
  final Color color;
  final Color textColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: DunesTypography.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: DunesColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.userId,
    required this.initial,
    required this.name,
    required this.role,
    required this.comment,
    required this.status,
    required this.statusColor,
    required this.avatarColor,
    required this.avatarTextColor,
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
    this.avatarService,
    this.isSelf = false,
  });

  final int userId;
  final String initial;
  final String name;
  final String role;
  final String comment;
  final String status;
  final Color statusColor;
  final Color avatarColor;
  final Color avatarTextColor;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;
  final ConversationService? avatarService;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImUserAvatar(
            initial: initial,
            seed: userId,
            size: 38,
            avatarPreset: avatarPreset.trim().isEmpty ? null : avatarPreset,
            avatarObjectKey:
                avatarObjectKey.trim().isEmpty ? null : avatarObjectKey,
            avatarUrl: avatarUrl.trim().isEmpty ? null : avatarUrl,
            avatarService: avatarService,
            fallbackBackground: avatarColor,
            fallbackForeground: avatarTextColor,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 5),
                      Text(
                        '本人',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          color: DunesColors.accent,
                        ),
                      ),
                    ],
                    const Spacer(),
                    _StatusPill(
                      label: status,
                      color: statusColor.withValues(alpha: 0.12),
                      textColor: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  role,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: isSelf && comment == '等待你填写意见'
                        ? DunesColors.text3
                        : DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
