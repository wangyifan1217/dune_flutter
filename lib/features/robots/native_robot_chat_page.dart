import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/http/session_http.dart';
import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_models.dart';
import '../conversation/reply_sla_models.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'robot_analyzing_coordinator.dart';
import 'robot_catalog_cache.dart';
import 'robot_character.dart';
import 'robot_consult_api.dart';
import 'robot_markdown.dart';
import 'robot_models.dart';
import '../conversation/chat_message_cache.dart';

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
  final Set<int> _confirmingAlertIds = {};
  final Map<int, GlobalKey> _messageKeys = {};
  bool _pendingConfirmVisible = true;

  /// 进会话贴底中：忽略短暂滚动偏移，避免 Markdown 撑高前误显「回到最新」。
  bool _enterStickBottomPending = false;
  int _scrollBottomGen = 0;
  String? _error;
  int _tempIdSeq = -1;
  Timer? _rtReloadDebounce;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  String? _selfAvatarPreset;
  String? _selfAvatarObjectKey;
  String? _selfAvatarUrl;

  /// 进页后短暂忽略 realtime 触发的 silent reload，避免 mark-read 推送造成二次拉消息。
  DateTime? _suppressRtReloadUntil;

  /// 下一轮静默刷新强制落库（忽略指纹短路），用于 ROBOT_REPLY 实时事件。
  bool _forceNextSilentReload = false;

  int get _convId => widget.conversationHint.id;
  String get _robotKey {
    final fromHint = widget.conversationHint.robotKey?.trim() ?? '';
    if (fromHint.isNotEmpty) return fromHint;
    return (widget.conversationHint.businessType ?? '').trim();
  }

  RobotAnalyzingCoordinator get _analyzing =>
      RobotAnalyzingCoordinator.instance;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _analyzing.bindSession(widget.session);
    // 离开再进：先用跨页状态恢复「正在分析」，避免等消息加载前空白。
    _waitingReply = _analyzing.isAnalyzing(_convId);
    // 优先用目录缓存判断 canChat / 头像配色，避免仅推送机器人首帧闪用灯塔紫。
    _role = RobotCatalogCache.instance.resolve(_robotKey);
    // 有缓存则立刻展示，不再整页转圈等网络。
    final cached = ChatMessageCache.instance.peek(_convId);
    if (cached != null && cached.isNotEmpty) {
      _messages.addAll(cached);
      _loading = false;
    }
    _scroll.addListener(_onScrollPosition);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    _applySelfAvatar(userAvatarRefresh.snapshotFor(widget.session.userId));
    // 已有头像缓存则不再打 /users/me，减少进页并发。
    if (_selfAvatarPreset == null &&
        (_selfAvatarObjectKey == null || _selfAvatarObjectKey!.isEmpty) &&
        (_selfAvatarUrl == null || _selfAvatarUrl!.isEmpty)) {
      unawaited(_loadSelfAvatar());
    }
    unawaited(_loadRole());
    unawaited(_bootstrap());
    _rtSub = ConversationRealtimeHub.instance
        .of(widget.session)
        .events
        .listen(_onRealtime);
    _analyzing.addListener(_onAnalyzingChanged);
  }

  void _onAnalyzingChanged() {
    if (!mounted || _convId <= 0) return;
    // 后台轮询确认回复已落库并清掉分析态时，强制刷一次会话（防实时丢包）。
    if (!_analyzing.isAnalyzing(_convId) && _waitingReply) {
      _forceNextSilentReload = true;
      unawaited(_reloadMessages(silent: true));
    }
  }

  @override
  void dispose() {
    _analyzing.removeListener(_onAnalyzingChanged);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    _rtSub?.cancel();
    _rtReloadDebounce?.cancel();
    _scroll.removeListener(_onScrollPosition);
    // active-view 由 Host 心跳统一管理，此处勿 clear，避免与 Host 竞态导致角标误亮。
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeRobotChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  void _onSelfAvatarUpdated() {
    _applySelfAvatar(userAvatarRefresh.snapshotFor(widget.session.userId));
  }

  void _applySelfAvatar(UserAvatarSnapshot? snap) {
    if (snap == null || !mounted) return;
    setState(() {
      _selfAvatarPreset = snap.avatarPreset.isEmpty ? null : snap.avatarPreset;
      _selfAvatarObjectKey = snap.avatarObjectKey.isEmpty
          ? null
          : snap.avatarObjectKey;
      _selfAvatarUrl = snap.avatarUrl.isEmpty ? null : snap.avatarUrl;
    });
  }

  Future<void> _loadSelfAvatar() async {
    try {
      final resp = await dunesHttpGet(widget.session, '/users/me');
      if (!mounted || resp.statusCode < 200 || resp.statusCode >= 300) return;
      final decoded = jsonDecode(resp.body);
      final data = decoded is Map
          ? (decoded['data'] is Map
                ? Map<String, dynamic>.from(decoded['data'] as Map)
                : Map<String, dynamic>.from(decoded))
          : const <String, dynamic>{};
      final preset = (data['avatarPreset'] ?? '').toString().trim();
      final objectKey = (data['avatarObjectKey'] ?? '').toString().trim();
      var avatarUrl = (data['avatarUrl'] ?? '').toString().trim();
      if (avatarUrl.isEmpty && objectKey.isNotEmpty) {
        avatarUrl = _service.mediaProxyUrl(objectKey, bucket: 'user-avatars');
      }
      final snapshot = UserAvatarSnapshot(
        userId: widget.session.userId,
        avatarPreset: preset,
        avatarObjectKey: objectKey,
        avatarUrl: avatarUrl,
      );
      userAvatarRefresh.remember(snapshot);
      _applySelfAvatar(snapshot);
    } catch (_) {}
  }

  Widget _selfAvatar() {
    final name = widget.session.displayName?.trim() ?? '';
    final initial = name.isNotEmpty ? name.substring(0, 1) : '我';
    return ImUserAvatar(
      initial: initial,
      seed: widget.session.userId,
      size: 45,
      avatarPreset: _selfAvatarPreset,
      avatarObjectKey: _selfAvatarObjectKey,
      avatarUrl: _selfAvatarUrl,
      avatarService: _service,
      borderRadius: 45 * 0.18,
    );
  }

  Future<void> _loadRole() async {
    final key = _robotKey;
    if (key.isEmpty) {
      if (!mounted) return;
      setState(() => _role = RobotCatalog.roleById('r_lighthouse'));
      return;
    }
    // 缓存命中且未过期：不再打 listRobots，避免进页额外 RTT + Header setState。
    final cached = RobotCatalogCache.instance.byKey(key);
    if (cached != null) {
      if (!identical(_role, cached) && mounted) {
        setState(() => _role = cached);
      }
      unawaited(RobotCatalogCache.instance.refresh(widget.session));
      return;
    }
    try {
      final list = await RobotCatalogCache.instance.refresh(widget.session);
      if (!mounted) return;
      final hit = list.where((r) => r.id == key).toList();
      final next = hit.isNotEmpty
          ? hit.first
          : RobotCatalogCache.instance.resolve(key);
      if (_role?.id == next.id &&
          _role?.accent == next.accent &&
          _role?.canChat == next.canChat) {
        return;
      }
      setState(() => _role = next);
    } catch (_) {
      if (!mounted) return;
      setState(() => _role = RobotCatalogCache.instance.resolve(key));
    }
  }

  Future<void> _bootstrap() async {
    final hasCache = _messages.isNotEmpty;
    setState(() {
      // 有缓存时后台刷新，不要再盖一层整页 Spinner。
      if (!hasCache) _loading = true;
      _error = null;
      _awayFromLatest = false;
      _enterStickBottomPending = true;
    });
    // mark-read 不阻塞首屏：先拉消息；进页 800ms 内忽略 realtime 二次 reload。
    _suppressRtReloadUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
    if (widget.autoMarkRead && _convId > 0) {
      unawaited(_markReadIfViewing());
    }
    if (_convId > 0) {
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(_convId),
      );
    }
    try {
      await _reloadMessages(stickToLatest: false, silent: hasCache);
    } catch (e) {
      if (mounted && !hasCache) {
        setState(() => _error = friendlyErrorText(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      // reverse 列表首帧即在最新端；仅补滚覆盖 Markdown/图片异步撑高。
      _scrollToLatestOnEnter();
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
      if (!mounted) return;
      widget.onConversationRead?.call(_convId);
    } catch (_) {}
  }

  Future<void> _reloadMessages({
    bool silent = false,
    bool stickToLatest = true,
  }) async {
    if (_convId <= 0) return;
    try {
      final page = await _service.fetchMessages(_convId, size: 30);
      if (!mounted) return;
      final prevLastId = _messages.isEmpty ? 0 : _messages.last.id;
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

      final force = _forceNextSilentReload;
      _forceNextSilentReload = false;
      if (!force &&
          silent &&
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
        // 首屏有数据后立刻挂载 reverse 列表（不必等 bootstrap finally），避免整页 Spinner→列表闪一下。
        if (!silent) _loading = false;
      });
      ChatMessageCache.instance.put(
        _convId,
        merged.where((m) => m.id > 0).toList(growable: false),
      );
      _syncAnalyzingFlag(
        nextWaiting,
        question: pendingLocal.isNotEmpty ? pendingLocal.last.bodyText : null,
      );
      final nextLastId = _messages.isEmpty ? 0 : _messages.last.id;
      // 正在查看时收到新回复必须再清一次未读（对齐审批助手），
      // 否则切到别的会话后 tab/列表仍会挂小红点。
      if (silent && nextLastId > prevLastId) {
        unawaited(_markReadIfViewing());
      } else if (freshReply && (wasWaiting || widget.autoMarkRead)) {
        unawaited(_markReadIfViewing());
      }
      if (!stickToLatest) {
        // bootstrap：列表已挂载，马上贴底（finally 还会再补一次）。
        if (!silent) _scrollToLatestOnEnter();
        return;
      }
      if (!_awayFromLatest) {
        _ensureScrolledToBottom(attempt: 0);
      } else {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _onScrollPosition(),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = friendlyErrorText(e));
      }
    }
  }

  void _onRealtime(ConversationRealtimeEvent ev) {
    if (ev.conversationId != _convId) return;
    if (ev.type == 'oil_fund_alert_ack' || ev.type == 'oil_fund_alert_read') {
      _applyOilFundAlertTiming(ev.raw, confirmed: ev.type == 'oil_fund_alert_ack');
      return;
    }
    if (ev.type != 'message' && ev.type != 'conversation_updated') return;
    final msg = ev.raw['message'];
    var gotRobotReply = false;
    if (msg is Map) {
      final kind = (msg['kind'] ?? '').toString().toUpperCase();
      if (kind == 'ROBOT_REPLY') {
        gotRobotReply = true;
        _analyzing.clear(_convId);
        // 先把实时消息塞进列表，避免「正在分析」被清掉后刷新失败/被短路导致空白。
        try {
          final mapped = _service.mapMessage(Map<String, dynamic>.from(msg));
          if (mounted) {
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == mapped.id);
              if (idx >= 0) {
                _messages[idx] = mapped;
              } else if (mapped.id > 0) {
                _messages.add(mapped);
                _messages.sort((a, b) => a.id.compareTo(b.id));
              }
              _waitingReply = false;
            });
            ChatMessageCache.instance.put(
              _convId,
              _messages.where((m) => m.id > 0).toList(growable: false),
            );
            if (!_awayFromLatest) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _jumpBottom();
              });
            }
          }
        } catch (_) {
          // 解析失败则仍走强制拉消息。
          if (mounted) setState(() => _waitingReply = false);
        }
      }
    }
    // 实时推送到达时先清未读，避免列表/角标短暂残留（对齐审批助手）。
    unawaited(_markReadIfViewing());
    final until = _suppressRtReloadUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      // 进页 mark-read / conversation_updated 不触发二次拉消息。
      if (ev.type == 'conversation_updated' && !gotRobotReply) return;
    }
    if (gotRobotReply || ev.type == 'message') {
      _forceNextSilentReload = true;
    }
    _rtReloadDebounce?.cancel();
    _rtReloadDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_reloadMessages(silent: true));
    });
  }

  bool get _isNearBottom {
    if (!_scroll.hasClients) return true;
    // reverse 列表：pixels 接近 0 即在最新消息端。
    return _scroll.position.pixels <= 72;
  }

  void _jumpBottom({bool animate = false}) {
    if (!_scroll.hasClients) return;
    // reverse 列表：0 = 最新消息端（靠近输入框）
    const target = 0.0;
    if (animate) {
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
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

  /// 进会话贴底：reverse 列表首帧已在底部，仅补滚覆盖 Markdown 异步撑高。
  void _scrollToLatestOnEnter() {
    _awayFromLatest = false;
    _enterStickBottomPending = true;
    _ensureScrolledToBottom(attempt: 0);
  }

  void _ensureScrolledToBottom({required int attempt}) {
    if (!mounted) return;
    if (!_enterStickBottomPending && _awayFromLatest && attempt > 0) return;
    final gen = ++_scrollBottomGen;
    _jumpBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _scrollBottomGen) return;
      if (_awayFromLatest && !_enterStickBottomPending) return;
      if (_isNearBottom || attempt >= 6) {
        _enterStickBottomPending = false;
        return;
      }
      final next = attempt + 1;
      final ms = next <= 2 ? 80 : 220;
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!mounted || gen != _scrollBottomGen) return;
        _ensureScrolledToBottom(attempt: next);
      });
    });
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    if (_enterStickBottomPending) return;
    // reverse 列表：上滑超过阈值才算离开最新。
    final away = _scroll.position.pixels > 140;
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
    _syncPendingConfirmVisible();
  }

  GlobalKey _messageKey(int id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  int? get _pendingConfirmMessageId {
    if (_robotKey != 'r_oil_fund_alert') return null;
    for (final m in _messages) {
      if (_oilFundAlertId(m) == null) continue;
      if (m.payload?['confirmed'] == true) continue;
      return m.id;
    }
    return null;
  }

  bool _messageInViewport(int id) {
    final itemContext = _messageKeys[id]?.currentContext;
    if (itemContext == null || !_scroll.hasClients) return false;
    final box = itemContext.findRenderObject();
    final viewport = _scroll.position.context.storageContext.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox || !box.hasSize) {
      return false;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + box.size.height;
    return bottom > 8 && top < viewport.size.height - 8;
  }

  void _syncPendingConfirmVisible() {
    final id = _pendingConfirmMessageId;
    final visible = id == null || _messageInViewport(id);
    if (visible == _pendingConfirmVisible || !mounted) return;
    setState(() => _pendingConfirmVisible = visible);
  }

  Future<void> _jumpToPendingConfirm() async {
    final id = _pendingConfirmMessageId;
    if (id == null) return;
    final itemContext = _messageKeys[id]?.currentContext;
    if (itemContext != null) {
      await Scrollable.ensureVisible(
        itemContext,
        alignment: 0.25,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      _syncPendingConfirmVisible();
      return;
    }
    if (!_scroll.hasClients) return;
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    final fromLatest = _messages.length - 1 - index;
    final guess = (fromLatest * 220.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    await _scroll.animateTo(
      guess,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    final built = _messageKeys[id]?.currentContext;
    if (built != null) {
      await Scrollable.ensureVisible(
        built,
        alignment: 0.25,
        duration: const Duration(milliseconds: 220),
      );
    }
    _syncPendingConfirmVisible();
  }

  void _dismissKeyboard() {
    if (_focus.hasFocus) _focus.unfocus();
  }

  Future<void> _showRobotReplyActions(
    NativeChatMessage message, {
    Offset? anchor,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: const Text('转发'),
                onTap: () => Navigator.pop(context, 'forward'),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('复制'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
              const Divider(height: 1),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') {
      await _copyRobotReply(message);
      return;
    }
    if (action == 'forward') {
      await _forwardRobotReply(message);
    }
  }

  Future<void> _copyRobotReply(NativeChatMessage message) async {
    final markdown = message.bodyText.trim();
    if (markdown.isEmpty) {
      showDunesToast(context, '暂无可复制内容');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: markdown));
      if (mounted) showDunesToast(context, '已复制');
    } catch (_) {
      if (mounted) {
        showDunesToast(context, '复制失败，请重试', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _forwardRobotReply(NativeChatMessage message) async {
    final markdown = message.bodyText.trim();
    if (markdown.isEmpty) {
      showDunesToast(context, '暂无可转发内容');
      return;
    }
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: _service,
      title: '转发至',
      highlightConversationId: _convId,
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;

    try {
      await _service.sendText(
        conversationId,
        markdown,
        payload: <String, dynamic>{
          'robotMarkdown': true,
          'robotKey': _robotKey,
          'robotName':
              (_role ?? RobotCatalogCache.instance.resolve(_robotKey)).name,
          'forwardedFromRobot': true,
        },
      );
      if (mounted) showDunesToast(context, '已转发');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
      }
    }
  }

  /// 与私聊 IM 对齐：输入框被点中后，键盘弹起前后均定位到最新消息。
  Future<void> _scrollToLatestForInput() async {
    _jumpBottom(animate: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (mounted && _focus.hasFocus) _jumpBottom();
  }

  bool get _canClearHistory => _robotKey != 'r_oil_fund_alert';

  Future<void> _confirmClearHistory() async {
    if (!_canClearHistory || _clearing || _convId <= 0) return;
    final role = _role ?? RobotCatalogCache.instance.resolve(_robotKey);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空会话？'),
        content: Text('将清空与「${role.name}」的 IM 聊天记录，仅对你不可见，不可恢复。'),
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
      ChatMessageCache.instance.remove(_convId);
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
    if (!_canChat) {
      showDunesToast(context, '该机器人仅推送，不支持回复');
      return;
    }
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
      final needConsultFallback =
          msg.contains('请通过机器人') ||
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

  bool get _canChat {
    final role = _role;
    if (role != null) return role.canChat;
    return RobotCatalogCache.instance.canChat(_robotKey);
  }

  @override
  Widget build(BuildContext context) {
    final role = _role ?? RobotCatalogCache.instance.resolve(_robotKey);
    final title = widget.conversationHint.title.trim().isNotEmpty
        ? widget.conversationHint.title.trim()
        : role.name;
    final canChat = _canChat;
    final subtitle = !canChat ? '仅推送通知' : (_waitingReply ? '正在分析…' : '文本追问');

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _dismissKeyboard(),
                child: Column(
                  children: [
                    ChatConvHeader(
                      title: title,
                      subtitle: subtitle,
                      onBack:
                          widget.onBack ?? () => Navigator.maybePop(context),
                      showBackButton: widget.showBackButton,
                      leadingAvatar: RobotFaceAvatar(
                        role: role,
                        size: 45,
                        animate: _waitingReply,
                        busy: _waitingReply,
                      ),
                      actions: [
                        if (_canClearHistory)
                        IconButton(
                          tooltip: '清空会话',
                          onPressed: (_clearing || _loading)
                              ? null
                              : _confirmClearHistory,
                          icon: _clearing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                          color: DunesColors.text2,
                        ),
                        if (canChat && widget.onOpenConsultList != null)
                          IconButton(
                            tooltip: '咨询明细',
                            onPressed: widget.onOpenConsultList,
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 20,
                            ),
                            color: DunesColors.text2,
                          ),
                      ],
                    ),
                    Expanded(child: _buildBody(role, canChat: canChat)),
                  ],
                ),
              ),
            ),
            if (canChat)
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
                showMobilePlusButton: false,
                onInputFocused: () => unawaited(_scrollToLatestForInput()),
                onTapOutside: _dismissKeyboard,
              )
            else
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: const BoxDecoration(
                    color: DunesColors.bgApp,
                    border: Border(
                      top: BorderSide(color: DunesColors.borderSoft),
                    ),
                  ),
                  child: Text(
                    '该机器人仅推送通知，不支持回复',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(RobotRole role, {required bool canChat}) {
    if (_error != null && _messages.isEmpty && !_loading) {
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
    if (_loading && _messages.isEmpty && !_waitingReply) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_messages.isEmpty && !_waitingReply) {
      return Center(
        child: Text(
          canChat ? '向「${role.name}」提问，回复会出现在这里' : '暂无推送消息',
          style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPendingConfirmVisible();
    });
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
            // 与私聊 IM 对齐：首帧即在最新消息端，避免进会话从顶跳到底。
            reverse: true,
            padding: EdgeInsets.fromLTRB(
              wide ? 16 : 12,
              12,
              wide ? 16 : 12,
              12,
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // reverse：index 0 = 最新（底部）；「正在分析」贴在最底。
              if (_waitingReply && index == 0) {
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
                      size: 45,
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
              final contentIndex = index - (_waitingReply ? 1 : 0);
              final msgIndex = _messages.length - 1 - contentIndex;
              final m = _messages[msgIndex];
              final mine = _isMine(m);
              final isRobot = m.kind.toUpperCase() == 'ROBOT_REPLY' || !mine;
              final isRobotReply = m.kind.toUpperCase() == 'ROBOT_REPLY';
              final timeLabel = InboxFormat.formatTime(
                m.createdAt,
                withClock: true,
              );
              return KeyedSubtree(
                key: _messageKey(m.id),
                child: ChatMessageRow(
                  message: m,
                  mine: mine,
                  showSenderMeta: !mine,
                  readLabel: null,
                  timeLabel: timeLabel,
                  showTimeForMine: mine,
                  onLongPressStart: isRobotReply
                      ? (details) => unawaited(
                          _showRobotReplyActions(
                            m,
                            anchor: details.globalPosition,
                          ),
                        )
                      : null,
                  onSecondaryTapDown: isRobotReply
                      ? (details) => unawaited(
                          _showRobotReplyActions(
                            m,
                            anchor: details.globalPosition,
                          ),
                        )
                      : null,
                  avatar: isRobot && !mine
                      ? RobotFaceAvatar(role: role, size: 45, animate: false)
                      : null,
                  trailingAvatar: mine ? _selfAvatar() : null,
                  content: mine
                      ? ChatTextBubble(text: m.bodyText, mine: true)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RobotReplyBubble(
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
                            if (_oilFundAlertId(m) != null)
                              _OilFundAlertConfirm(
                                message: m,
                                confirming: _confirmingAlertIds.contains(
                                  _oilFundAlertId(m),
                                ),
                                onConfirm: () => unawaited(_confirmOilFundAlert(m)),
                              ),
                            if (isRobotReply)
                              _RobotReplyQuickActions(
                                onCopy: () => unawaited(_copyRobotReply(m)),
                                onForward: () =>
                                    unawaited(_forwardRobotReply(m)),
                              ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
        if (_pendingConfirmMessageId != null && !_pendingConfirmVisible)
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => unawaited(_jumpToPendingConfirm()),
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: const Color(0xFFD4380D),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '去确认',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

  int? _oilFundAlertId(NativeChatMessage m) {
    final key = '${m.payload?['robotKey'] ?? ''}'.trim();
    if (key.isNotEmpty && key != 'r_oil_fund_alert') return null;
    final raw = m.payload?['alertId'];
    if (raw == null) return null;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  void _applyOilFundAlertTiming(
    Map<String, dynamic> raw, {
    required bool confirmed,
  }) {
    final messageId = raw['messageId'];
    final id = messageId is num
        ? messageId.toInt()
        : int.tryParse('$messageId');
    if (id == null) return;
    setState(() {
      final index = _messages.indexWhere((item) => item.id == id);
      if (index < 0) return;
      final next = Map<String, dynamic>.from(_messages[index].payload ?? {});
      for (final key in ['pushedAt', 'readAt', 'confirmedAt', 'unreadMs', 'confirmWaitMs']) {
        if (raw[key] != null) next[key] = raw[key];
      }
      if (confirmed) next['confirmed'] = true;
      _messages[index] = _messages[index].copyWith(payload: next);
    });
  }

  Future<void> _confirmOilFundAlert(NativeChatMessage message) async {
    final alertId = _oilFundAlertId(message);
    if (alertId == null || _confirmingAlertIds.contains(alertId)) return;
    if (message.payload?['confirmed'] == true) return;
    setState(() => _confirmingAlertIds.add(alertId));
    try {
      final data = await _service.ackOilFundAlert(alertId);
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          final next = Map<String, dynamic>.from(
            _messages[index].payload ?? {},
          );
          next['confirmed'] = true;
          for (final key in [
            'pushedAt',
            'readAt',
            'confirmedAt',
            'unreadMs',
            'confirmWaitMs',
          ]) {
            if (data[key] != null) next[key] = data[key];
          }
          _messages[index] = _messages[index].copyWith(payload: next);
        }
      });
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '确认失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _confirmingAlertIds.remove(alertId));
    }
  }
}

/// 对方气泡样式对齐 [ChatTextBubble]；宽表靠横向滚动，气泡宽度钉死避免撑破整页。
class _RobotReplyBubble extends StatelessWidget {
  const _RobotReplyBubble({required this.child, this.wide = false});

  final Widget child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    // 手机：留给头像+边距后尽量宽；宽屏：上限放宽，便于多列表格。
    final preferredMax = wide
        ? (screenW * 0.55).clamp(420.0, 640.0)
        : (screenW - 72).clamp(260.0, 420.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final maxW = available.isFinite && available > 0
            ? (available < preferredMax ? available : preferredMax)
            : preferredMax;
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: maxW,
            clipBehavior: Clip.hardEdge,
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
          ),
        );
      },
    );
  }
}

class _OilFundAlertConfirm extends StatefulWidget {
  const _OilFundAlertConfirm({
    required this.message,
    required this.confirming,
    required this.onConfirm,
  });

  final NativeChatMessage message;
  final bool confirming;
  final VoidCallback onConfirm;

  @override
  State<_OilFundAlertConfirm> createState() => _OilFundAlertConfirmState();
}

class _OilFundAlertConfirmState extends State<_OilFundAlertConfirm> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _OilFundAlertConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final confirmed = widget.message.payload?['confirmed'] == true;
    if (confirmed) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  DateTime? _timeOf(String key) {
    final raw = '${widget.message.payload?[key] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final pushed = _timeOf('pushedAt') ?? widget.message.createdAt?.toLocal();
    final read = _timeOf('readAt');
    final confirmedAt = _timeOf('confirmedAt');
    final confirmed = widget.message.payload?['confirmed'] == true;
    final readDur = read != null && pushed != null
        ? formatReplySlaDuration(read.difference(pushed))
        : null;
    final pendingDur = !confirmed && read != null
        ? formatReplySlaDuration(now.difference(read))
        : null;
    final unreadLive = !confirmed && read == null && pushed != null
        ? formatReplySlaDuration(now.difference(pushed))
        : null;
    final waitDur = confirmed && confirmedAt != null && pushed != null
        ? formatReplySlaDuration(confirmedAt.difference(pushed))
        : null;

    String status;
    Color color;
    if (confirmed) {
      final readPart = readDur == null ? '已读' : '已读 $readDur';
      status = waitDur == null ? '$readPart · 已确认' : '$readPart · 已确认 用时 $waitDur';
      color = DunesColors.readReceipt;
    } else if (read != null) {
      status = pendingDur == null ? '已读 · 未确认' : '已读 · 未确认 $pendingDur';
      color = const Color(0xFFD4380D);
    } else {
      status = unreadLive == null ? '未读' : '未读 $unreadLive';
      color = DunesColors.text3;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: DunesTypography.sans(fontSize: 12, color: color),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: confirmed || widget.confirming ? null : widget.onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(
              confirmed ? '已确认' : (widget.confirming ? '确认中…' : '确认'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RobotReplyQuickActions extends StatelessWidget {
  const _RobotReplyQuickActions({
    required this.onCopy,
    required this.onForward,
  });

  final VoidCallback onCopy;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '复制',
            onPressed: onCopy,
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            color: DunesColors.text3,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: '转发',
            onPressed: onForward,
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            color: DunesColors.text3,
            icon: const Icon(Icons.shortcut_rounded),
          ),
        ],
      ),
    );
  }
}
