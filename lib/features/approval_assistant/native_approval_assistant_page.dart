import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/assistant_transcript_support.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../shell/dunes_toast.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/proposal_upload_config.dart';
import '../xflow/xflow_detail_logic.dart';
import 'approval_urge_send_sheet.dart';

enum ApprovalAssistantPickMode { browse, explain, urge }

/// 审批助手只读会话：消息流 + 底部三按钮（无输入框）。
class NativeApprovalAssistantPage extends StatefulWidget {
  const NativeApprovalAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onBack,
    this.onConversationRead,
    this.onOpenPendingList,
    this.onOpenProposals,
    this.onOpenApproval,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;
  final void Function(ApprovalAssistantPickMode mode)? onOpenPendingList;
  final VoidCallback? onOpenProposals;
  final ValueChanged<ApprovalChatShare>? onOpenApproval;

  @override
  State<NativeApprovalAssistantPage> createState() =>
      _NativeApprovalAssistantPageState();
}

class _NativeApprovalAssistantPageState
    extends State<NativeApprovalAssistantPage> {
  late final ConversationService _service;
  final _scroll = ScrollController();
  final List<NativeChatMessage> _messages = [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _clearing = false;
  bool _awayFromLatest = false;
  String? _error;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtReloadDebounce;

  /// ensure 后得到的真实会话 id（hint.id 可能为 0）。
  int? _resolvedConvId;

  int get _convId {
    final hintId = widget.conversationHint.id;
    if (hintId > 0) return hintId;
    return _resolvedConvId ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scroll.addListener(_onScrollPosition);
    _bootstrap();
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _rtSub = realtime.events.listen(_onRealtime);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtReloadDebounce?.cancel();
    _scroll.removeListener(_onScrollPosition);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeApprovalAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // PC 最小化/失焦期间 autoMarkRead=false，新消息会进屏但不上报已读；
    // 恢复前台后必须补一次，否则托盘会继续按服务端未读闪烁。
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _awayFromLatest = false;
    });
    try {
      var convId = _convId;
      if (convId <= 0) {
        final ensured = await _service.ensureApprovalAssistantSession();
        convId = ensured.id;
        if (convId <= 0) {
          throw Exception('审批助手会话无效');
        }
        if (!mounted) return;
        _resolvedConvId = convId;
      }
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(convId),
      );
      if (widget.autoMarkRead) {
        await _service.markConversationRead(convId);
        widget.onConversationRead?.call(convId);
      }
      await _reloadMessagesFor(convId);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToLatestOnEnter();
    }
  }

  Future<void> _reloadMessagesFor(int convId, {bool silent = false}) async {
    try {
      final page = await _service.fetchMessagePage(convId);
      if (!mounted) return;
      final prevLastId = _messages.isEmpty ? 0 : _messages.last.id;
      final stick = !_awayFromLatest;
      setState(() {
        final next = silent
            ? mergeLatestAssistantMessages(
                current: List<NativeChatMessage>.from(_messages),
                latest: page.items,
              )
            : page.items;
        _messages
          ..clear()
          ..addAll(next);
        if (!silent) {
          _hasMore = page.hasMore;
          _error = null;
        }
      });
      final nextLastId = _messages.isEmpty ? 0 : _messages.last.id;
      if (silent && nextLastId > prevLastId) {
        unawaited(_markReadIfViewing());
      }
      if (stick) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = friendlyErrorText(e));
      }
    }
  }

  Future<void> _reloadMessages({bool silent = false}) async {
    if (_convId <= 0) {
      if (!silent) {
        throw Exception('审批助手会话无效');
      }
      return;
    }
    await _reloadMessagesFor(_convId, silent: silent);
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || _convId <= 0) return;
    // PC 最小化/失焦/托盘时禁止已读上报，保持未读并驱动托盘闪烁。
    if (windowsTrayIsWindowInactive()) return;
    try {
      await _service.markConversationRead(_convId);
      if (!mounted) return;
      widget.onConversationRead?.call(_convId);
    } catch (_) {}
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    final convId = _convId;
    if (convId <= 0 || event.conversationId != convId) return;
    if (event.type != 'message' && event.type != 'conversation_updated') {
      return;
    }
    // 催办/解释完成后服务端会原地更新同一条 pending 消息（updated:true）。
    // 先按 id upsert，避免只靠 silent reload 时界面仍停在「正在生成…」。
    if (event.type == 'message') {
      _upsertRealtimeMessage(event);
    }
    // 实时推送到达时先清未读，避免列表/角标短暂残留。
    unawaited(_markReadIfViewing());
    _rtReloadDebounce?.cancel();
    _rtReloadDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      unawaited(_reloadMessages(silent: true));
    });
  }

  void _upsertRealtimeMessage(ConversationRealtimeEvent event) {
    final raw = event.raw['message'];
    if (raw is! Map) return;
    try {
      final msg = _service.mapMessage(Map<String, dynamic>.from(raw));
      if (msg.id <= 0 || !mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          _messages[idx] = msg;
        } else {
          _messages.add(msg);
          _messages.sort((a, b) => a.id.compareTo(b.id));
        }
      });
      if (!_awayFromLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _jumpBottom();
        });
      }
    } catch (_) {
      // 解析失败时仍走下方 silent reload 兜底。
    }
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final away = assistantIsAwayFromLatest(pos);
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
    if (assistantShouldLoadOlder(
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      pos: pos,
    )) {
      unawaited(_loadOlder());
    }
  }

  void _scrollToLatestOnEnter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpBottom();
      Future<void>.delayed(const Duration(milliseconds: 80), _jumpBottom);
      Future<void>.delayed(const Duration(milliseconds: 240), _jumpBottom);
    });
  }

  void _jumpBottom({bool animate = false}) {
    if (!_scroll.hasClients) return;
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
    if (_awayFromLatest && mounted) {
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
      final page = await _service.fetchMessagePage(_convId, before: firstId);
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

  Future<void> _confirmClearHistory() async {
    if (_clearing || _convId <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空会话？'),
        content: const Text('将清空审批助手的聊天记录，仅对你不可见，不可恢复。'),
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
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _awayFromLatest = false;
        _hasMore = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '审批助手',
              subtitle: _loading ? '加载中…' : '',
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
              leadingAvatar: const ApprovalAssistantAvatar(size: 45),
              actions: [
                IconButton(
                  tooltip: '一键清空',
                  onPressed: (_clearing || _loading || _convId <= 0)
                      ? null
                      : _confirmClearHistory,
                  icon: _clearing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline_rounded, size: 20),
                  color: DunesColors.text2,
                ),
              ],
            ),
            Expanded(child: _buildBody()),
            _BottomActions(
              onPending: () => widget.onOpenPendingList
                  ?.call(ApprovalAssistantPickMode.browse),
              onProposals: () => widget.onOpenProposals?.call(),
              onExplain: () => widget.onOpenPendingList
                  ?.call(ApprovalAssistantPickMode.explain),
              onUrge: () => widget.onOpenPendingList
                  ?.call(ApprovalAssistantPickMode.urge),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
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
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '每天上午 9 点会推送简报（待我审批 + 我发起进行中）。\n也可点下方按钮查看待办、解释或催办。',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3),
          ),
        ),
      );
    }

    final wide = isWideChatLayout(context);
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 12, wide ? 16 : 12, 12),
          itemCount: _messages.length + (_loadingOlder ? 1 : 0),
          itemBuilder: (context, index) {
            if (_loadingOlder && index == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final m = _messages[_loadingOlder ? index - 1 : index];
            final payload = m.payload ?? const <String, dynamic>{};
            final type = (payload['type'] ?? '').toString();
            return ChatMessageRow(
              message: m,
              mine: false,
              showSenderMeta: true,
              readLabel: null,
              timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
              avatar: const ApprovalAssistantAvatar(size: 45),
              content: _buildMessageContent(m, type, payload),
            );
          },
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

  Widget _buildMessageContent(
    NativeChatMessage m,
    String type,
    Map<String, dynamic> payload,
  ) {
    if (type == 'approvalBrief') {
      return _BriefCard(
        payload: payload,
        fallback: m.bodyText,
        onOpenAll: () =>
            widget.onOpenPendingList?.call(ApprovalAssistantPickMode.browse),
      );
    }
    if (type == 'approvalComment') {
      final share = ApprovalChatShare.fromPayload(payload);
      final author = (payload['authorDisplayName'] ?? '').toString().trim();
      final body = (payload['bodyText'] ?? m.bodyText).toString().trim();
      final mentioned = payload['mentionedMe'] == true;
      final repliedToMe = payload['repliedToMe'] == true;
      final parentId = (payload['parentId'] as num?)?.toInt() ?? 0;
      final parentAuthor =
          (payload['parentAuthorDisplayName'] ?? '').toString().trim();
      final parentBody = (payload['parentBodyText'] ?? '').toString().trim();
      final isReply = parentId > 0 && parentAuthor.isNotEmpty;
      final who = author.isEmpty ? '有人' : author;
      String? tip;
      if (isReply) {
        tip = repliedToMe
            ? '$who 回复了你的评论'
            : '$who 回复了 $parentAuthor 的评论';
      } else if (mentioned) {
        tip = '有人在审批评论中 @ 了你';
      }
      final bubbleText = isReply
          ? body
          : (author.isEmpty ? body : '$author：\n$body');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                tip,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isReply
                      ? DunesColors.brandPurpleDeep
                      : const Color(0xFFB07A2B),
                ),
              ),
            ),
          if (isReply && parentBody.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DunesColors.borderSoft),
              ),
              child: Text(
                '$parentAuthor：$parentBody',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 12,
                  height: 1.4,
                  color: DunesColors.text3,
                ),
              ),
            ),
          ],
          ChatTextBubble(
            text: bubbleText,
            mine: false,
          ),
          if (share != null) ...[
            const SizedBox(height: 8),
            _approvalCardWidget(share),
          ],
        ],
      );
    }
    final share = ApprovalChatShare.fromPayload(payload);
    // 协作提案：正文说明要对方做什么，名片只承担入口。
    if (share != null &&
        (type == 'approvalCard' || type.isEmpty || type == 'approvalShare')) {
      final instruction = ApprovalChatShare.assistantInstruction(
        share: share,
        bodyText: m.bodyText,
        payload: payload,
      );
      if (instruction != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChatTextBubble(text: instruction, mine: false),
            const SizedBox(height: 8),
            _approvalCardWidget(share),
          ],
        );
      }
      return _approvalCardWidget(share);
    }
    if (type == 'approvalExplain' ||
        type == 'approvalExplainPending' ||
        type == 'approvalUrge' ||
        type == 'approvalUrgePending') {
      return _buildComboResult(m, type, payload);
    }
    return ChatTextBubble(text: m.bodyText, mine: false);
  }

  Widget _buildComboResult(
    NativeChatMessage m,
    String type,
    Map<String, dynamic> payload,
  ) {
    final status = (payload['status'] ?? '').toString();
    final pending = status == 'pending' ||
        type == 'approvalExplainPending' ||
        type == 'approvalUrgePending';
    final failed = status == 'failed';
    final sent = status == 'sent';
    final isUrge = type == 'approvalUrge' || type == 'approvalUrgePending';
    final share = ApprovalChatShare.fromPayload(payload);
    final body = isUrge
        ? (payload['draft'] ?? m.bodyText).toString().trim()
        : (payload['markdown'] ?? m.bodyText).toString().trim();
    final suggest = <UrgeSuggestTarget>[];
    final rawTargets = payload['suggestTargets'];
    if (rawTargets is List) {
      for (final item in rawTargets) {
        if (item is! Map) continue;
        final uid = (item['userId'] as num?)?.toInt() ??
            (item['id'] as num?)?.toInt() ??
            0;
        if (uid <= 0) continue;
        final name = (item['displayName'] ?? '用户$uid').toString();
        suggest.add(UrgeSuggestTarget(userId: uid, displayName: name));
      }
    }

    return _ComboResultBubble(
      pending: pending,
      failed: failed,
      pendingText: m.bodyText,
      sectionTitle: isUrge
          ? (sent ? '催办话术（已发送）' : '催办话术')
          : '单据解释',
      body: body.isEmpty ? m.bodyText : body,
      asMarkdown: !isUrge && !failed && !pending,
      card: share == null
          ? null
          : _approvalCardWidget(
              ApprovalChatShare(
                businessType: share.businessType,
                businessId: share.businessId,
                title: _approvalCardTitle(share),
                status: share.status,
                templateKey: share.templateKey,
                code: share.code,
                submitterName: share.submitterName,
                actionLabel: share.actionLabel,
              ),
            ),
      actionLabel: isUrge && !failed && !pending && !sent && (share?.businessId ?? 0) > 0
          ? '选择发送对象'
          : null,
      onAction: isUrge && !failed && !pending && !sent && share != null
          ? () {
              unawaited(
                showApprovalUrgeSendSheet(
                  context: context,
                  session: widget.session,
                  share: ApprovalChatShare(
                    businessType: share.businessType,
                    businessId: share.businessId,
                    title: _approvalCardTitle(share),
                    status: share.status,
                    templateKey: share.templateKey,
                    code: share.code,
                    submitterName: share.submitterName,
                    actionLabel: share.actionLabel,
                  ),
                  draft: body.isEmpty ? m.bodyText : body,
                  suggestTargets: suggest,
                  sourceMessageId: m.id,
                ),
              );
            }
          : null,
    );
  }

  Widget _approvalCardWidget(ApprovalChatShare share) {
    return ChatApprovalCard(
      title: _approvalCardTitle(share),
      statusLabel: share.isProposalIntake || share.isTaskTodo
          ? ''
          : detailStatusLabel(share.status),
      subtitle: share.isTaskTodo
          ? share.taskCardLine
          : share.isProposalIntake
          ? share.proposalCardLine
          : share.businessType.toUpperCase() == 'PROPOSAL'
          ? '销售提案'
          : '审批单据',
      brandLabel: share.isTaskTodo
          ? '审批待办'
          : share.isProposalIntake
          ? '协作提案'
          : '沙丘审批',
      subtitleMaxLines: share.isProposalIntake || share.isTaskTodo ? 2 : 1,
      onTap: () => widget.onOpenApproval?.call(share),
    );
  }

  /// 兼容助手早期生成的「审批单 #11」等泛标题，展示时对齐 IM 转发。
  String _approvalCardTitle(ApprovalChatShare card) {
    final raw = card.title.trim();
    final kind = proposalKindLabel(
      templateKey: card.templateKey,
      businessType: card.businessType,
    );
    final bt = card.businessType.trim();
    final generic = raw.isEmpty ||
        raw == bt ||
        raw.toUpperCase() == bt.toUpperCase() ||
        raw.startsWith('$bt #') ||
        RegExp(r'^审批单\s*#?\d+$').hasMatch(raw) ||
        RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(raw);
    return generic ? kind : raw;
  }
}

class _ComboResultBubble extends StatelessWidget {
  const _ComboResultBubble({
    required this.pending,
    required this.failed,
    required this.pendingText,
    required this.sectionTitle,
    required this.body,
    required this.asMarkdown,
    this.card,
    this.actionLabel,
    this.onAction,
  });

  final bool pending;
  final bool failed;
  final String pendingText;
  final String sectionTitle;
  final String body;
  final bool asMarkdown;
  final Widget? card;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: failed ? DunesColors.coralSoft : DunesColors.brandPurpleSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: failed
              ? DunesColors.coral.withValues(alpha: 0.35)
              : DunesColors.brandPurpleLine,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pendingText.trim().isEmpty ? '处理中…' : pendingText,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.text2,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (card != null) ...[
              card!,
              const SizedBox(height: 10),
            ],
            Text(
              sectionTitle,
              style: DunesTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: DunesColors.brandPurpleDeep,
              ),
            ),
            const SizedBox(height: 8),
            if (failed)
              Text(
                body,
                style: DunesTypography.sans(
                  fontSize: 13,
                  height: 1.45,
                  color: DunesColors.coral,
                ),
              )
            else if (asMarkdown)
              MarkdownBody(
                data: body,
                softLineBreak: true,
                styleSheet: MarkdownStyleSheet(
                  p: DunesTypography.sans(
                    fontSize: 13,
                    height: 1.5,
                    color: DunesColors.text,
                  ),
                  h1: DunesTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.brandPurpleDeep,
                  ),
                  h2: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.brandPurpleDeep,
                  ),
                  h3: DunesTypography.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.brandPurpleDeep,
                  ),
                  strong: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                  listBullet: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text2,
                  ),
                  a: const TextStyle(
                    fontFamily: 'Noto Sans SC',
                    fontSize: 13,
                    color: DunesColors.brandPurpleDeep,
                    decoration: TextDecoration.underline,
                  ),
                ),
              )
            else
              Text(
                body,
                style: DunesTypography.sans(
                  fontSize: 13,
                  height: 1.5,
                  color: DunesColors.text,
                ),
              ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: DunesColors.brandPurpleDeep,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class ApprovalAssistantAvatar extends StatelessWidget {
  const ApprovalAssistantAvatar({super.key, this.size = 45});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.18;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DunesColors.brandPurple, DunesColors.brandPurpleDeep],
        ),
      ),
      child: Icon(
        Icons.fact_check_outlined,
        color: Colors.white,
        size: size * 0.42,
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.onPending,
    required this.onProposals,
    required this.onExplain,
    required this.onUrge,
  });

  final VoidCallback onPending;
  final VoidCallback onProposals;
  final VoidCallback onExplain;
  final VoidCallback onUrge;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10, 8, 10, bottom > 0 ? bottom + 6 : 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ActionBtn(
              label: '今日待审',
              icon: Icons.inbox_outlined,
              primary: true,
              onTap: onPending,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActionBtn(
              label: '提案审核',
              icon: Icons.assignment_outlined,
              primary: true,
              onTap: onProposals,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActionBtn(
              label: '解释内容',
              icon: Icons.menu_book_outlined,
              onTap: onExplain,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ActionBtn(
              label: '催办进度',
              icon: Icons.campaign_outlined,
              onTap: onUrge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? DunesColors.brandPurple : DunesColors.brandPurpleSoft,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: primary ? Colors.white : DunesColors.brandPurpleDeep,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primary ? Colors.white : DunesColors.brandPurpleDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BriefCard extends StatelessWidget {
  const _BriefCard({
    required this.payload,
    required this.fallback,
    required this.onOpenAll,
  });

  final Map<String, dynamic> payload;
  final String fallback;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final pending = (payload['pendingCount'] as num?)?.toInt() ?? 0;
    final o24 = (payload['overdue24hCount'] as num?)?.toInt() ?? 0;
    final o1w = (payload['overdue1wCount'] as num?)?.toInt() ?? 0;
    final initiated = (payload['initiatedCount'] as num?)?.toInt() ?? 0;
    final pendingTypes = _typeCountRows(payload['pendingTypeCounts']);
    final initiatedTypes = _typeCountRows(payload['initiatedTypeCounts']);
    final showPending = pending > 0 || initiated <= 0;
    final showInitiated = initiated > 0;
    final overdue = <String>[
      if (o24 > 0) '超24h $o24',
      if (o1w > 0) '超1周 $o1w',
    ].join(' · ');

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: DunesColors.brandPurpleLine.withValues(alpha: 0.75),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F3A2A6A),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日审批简报',
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.brandPurpleDeep,
              letterSpacing: 0.1,
            ),
          ),
          if (pending <= 0 && initiated <= 0) ...[
            const SizedBox(height: 4),
            Text(
              fallback.isEmpty ? '暂无待审' : fallback,
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            // 待我审批为主视觉，我发起为次要块（等高不再强制撑开）。
            if (showPending && showInitiated)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _BriefMetric(
                      label: '待我审批',
                      value: pending,
                      hint: overdue,
                      large: true,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 4,
                    child: _BriefMetric(
                      label: '我发起进行中',
                      value: initiated,
                      compact: true,
                    ),
                  ),
                ],
              )
            else if (showPending)
              _BriefMetric(
                label: '待我审批',
                value: pending,
                hint: overdue,
                large: true,
              )
            else
              _BriefMetric(
                label: '我发起进行中',
                value: initiated,
                large: true,
              ),
            if (pendingTypes.isNotEmpty) ...[
              const SizedBox(height: 5),
              _BriefTypeBlock(title: '待我审批', rows: pendingTypes),
            ],
            if (initiatedTypes.isNotEmpty) ...[
              const SizedBox(height: 4),
              _BriefTypeBlock(title: '我发起进行中', rows: initiatedTypes),
            ],
          ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onOpenAll,
              style: TextButton.styleFrom(
                foregroundColor: DunesColors.brandPurpleDeep,
                backgroundColor: DunesColors.brandPurpleSoft,
                padding: const EdgeInsets.symmetric(vertical: 3),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                '查看列表',
                style: DunesTypography.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.brandPurpleDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, int)> _typeCountRows(dynamic raw) {
    if (raw is! List) return const [];
    final out = <(String, int)>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final type = (item['type'] ?? item['name'] ?? '').toString().trim();
      final count = (item['count'] as num?)?.toInt() ?? 0;
      if (type.isEmpty || count <= 0) continue;
      out.add((type, count));
    }
    return out;
  }
}

class _BriefMetric extends StatelessWidget {
  const _BriefMetric({
    required this.label,
    required this.value,
    this.hint = '',
    this.large = false,
    this.compact = false,
  });

  final String label;
  final int value;
  final String hint;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueSize = large ? 14.0 : (compact ? 12.0 : 13.0);
    final pad = compact
        ? const EdgeInsets.fromLTRB(5, 4, 5, 4)
        : const EdgeInsets.fromLTRB(6, 4, 6, 4);
    return Container(
      width: double.infinity,
      padding: pad,
      decoration: BoxDecoration(
        color: large
            ? DunesColors.brandPurpleSoft
            : const Color(0xFFF7F5FB),
        borderRadius: BorderRadius.circular(6),
        border: large
            ? null
            : Border.all(
                color: DunesColors.brandPurpleLine.withValues(alpha: 0.45),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: compact ? 9 : 10,
              height: 1.1,
              color: DunesColors.text3,
            ),
          ),
          SizedBox(height: compact ? 2 : 1),
          Text(
            '$value',
            style: DunesTypography.sans(
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
              height: 1.05,
              color: DunesColors.brandPurpleDeep,
            ),
          ),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB45309),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BriefTypeBlock extends StatelessWidget {
  const _BriefTypeBlock({required this.title, required this.rows});

  final String title;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: DunesTypography.sans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: DunesColors.text3,
          ),
        ),
        const SizedBox(height: 2),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              color: DunesColors.brandPurpleLine.withValues(alpha: 0.35),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${rows[i].$2}',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.brandPurpleDeep,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
