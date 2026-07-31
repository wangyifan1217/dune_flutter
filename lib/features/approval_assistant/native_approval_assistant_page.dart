import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

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
    this.onOpenApproval,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;
  final void Function(ApprovalAssistantPickMode mode)? onOpenPendingList;
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
  bool _clearing = false;
  bool _awayFromLatest = false;
  String? _error;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtReloadDebounce;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scroll.addListener(_onScrollPosition);
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
    _scroll.dispose();
    super.dispose();
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
        // conversationHint 是 final，用本地覆盖后续拉取。
        if (!mounted) return;
        // 通过重新加载消息使用新 id：暂存到 messages 拉取参数。
        await _reloadMessagesFor(convId);
        if (widget.autoMarkRead) {
          await _service.markConversationRead(convId);
          widget.onConversationRead?.call(convId);
        }
        return;
      }
      if (widget.autoMarkRead) {
        await _service.markConversationRead(convId);
        widget.onConversationRead?.call(convId);
      }
      await _reloadMessages();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToLatestOnEnter();
    }
  }

  Future<void> _reloadMessagesFor(int convId, {bool silent = false}) async {
    final list = await _service.fetchMessages(convId);
    if (!mounted) return;
    final prevLastId = _messages.isEmpty ? 0 : _messages.last.id;
    final stick = !_awayFromLatest;
    setState(() {
      _messages
        ..clear()
        ..addAll(list);
      if (!silent) _error = null;
    });
    final nextLastId = _messages.isEmpty ? 0 : _messages.last.id;
    if (silent && nextLastId > prevLastId) {
      unawaited(_markReadIfViewing());
    }
    if (stick) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
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
    try {
      await _service.markConversationRead(_convId);
      if (!mounted) return;
      widget.onConversationRead?.call(_convId);
    } catch (_) {}
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (event.conversationId != _convId) return;
    if (event.type != 'message' && event.type != 'conversation_updated') {
      return;
    }
    // 实时推送到达时先清未读，避免列表/角标短暂残留。
    unawaited(_markReadIfViewing());
    _rtReloadDebounce?.cancel();
    _rtReloadDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      unawaited(_reloadMessages(silent: true));
    });
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final away = max - _scroll.position.pixels > 140;
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
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
          padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 12, wide ? 16 : 12, 12),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final m = _messages[index];
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
                          color: DunesColors.brandPurpleDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '回到最新',
                          style: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.brandPurpleDeep,
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
    // 旧版单独名片消息仍保留。
    if (share != null &&
        (type == 'approvalCard' || type.isEmpty || type == 'approvalShare')) {
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
      statusLabel: detailStatusLabel(share.status),
      subtitle: share.businessType.toUpperCase() == 'PROPOSAL'
          ? '销售提案'
          : '审批单据',
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
    required this.onExplain,
    required this.onUrge,
  });

  final VoidCallback onPending;
  final VoidCallback onExplain;
  final VoidCallback onUrge;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottom > 0 ? bottom + 8 : 12),
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
          const SizedBox(width: 8),
          Expanded(
            child: _ActionBtn(
              label: '解释内容',
              icon: Icons.menu_book_outlined,
              onTap: onExplain,
            ),
          ),
          const SizedBox(width: 8),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(
                icon,
                size: 18,
                color: primary ? Colors.white : DunesColors.brandPurpleDeep,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : DunesColors.brandPurpleDeep,
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
