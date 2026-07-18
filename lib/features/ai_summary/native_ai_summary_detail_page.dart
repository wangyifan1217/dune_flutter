import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../meeting/meeting_minutes_markdown.dart';
import '../shell/dunes_toast.dart';
import 'ai_summary_models.dart';
import 'ai_summary_participants.dart';
import 'ai_summary_service.dart';

/// 智能总结详情：Markdown 正文 + 参与会话 + 异步刷新。
class NativeAiSummaryDetailPage extends StatefulWidget {
  const NativeAiSummaryDetailPage({
    super.key,
    required this.session,
    required this.summaryId,
    required this.onBack,
  });

  final AuthSession session;
  final int summaryId;
  final VoidCallback onBack;

  @override
  State<NativeAiSummaryDetailPage> createState() =>
      _NativeAiSummaryDetailPageState();
}

class _NativeAiSummaryDetailPageState extends State<NativeAiSummaryDetailPage> {
  late final AiSummaryService _service;
  late final ConversationService _conversations;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _pollTimer;

  bool _loading = true;
  String? _error;
  AiSummaryItem? _item;
  List<NativeConversation> _participantConversations =
      const <NativeConversation>[];
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _service = AiSummaryService(session: widget.session);
    _conversations = ConversationService(session: widget.session);
    _rtSub = ConversationRealtimeHub.instance
        .of(widget.session)
        .events
        .listen(_onRealtime);
    unawaited(_load());
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (event.type != 'ai_summary_updated') return;
    final update = AiSummaryRealtimeUpdate.fromPayload(event.raw);
    if (update.id != widget.summaryId) return;
    unawaited(_load(silent: true));
  }

  Future<void> _hydrateParticipants(AiSummaryItem item) async {
    final list = await resolveAiSummaryConversations(
      service: _conversations,
      conversationIds: item.conversationIds,
    );
    if (!mounted) return;
    setState(() => _participantConversations = list);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final item = await _service.fetchDetail(widget.summaryId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
        _error = null;
      });
      _syncPoll(item);
      unawaited(_hydrateParticipants(item));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '详情加载失败');
      });
    }
  }

  void _syncPoll(AiSummaryItem item) {
    if (!item.isGenerating) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_load(silent: true));
    });
  }

  Future<DateTimeRange?> _pickRangeForRegenerate(AiSummaryItem item) async {
    final picked = await pickAiSummaryDateRange(
      context: context,
      initial: aiSummaryInclusiveRangeFromApi(item.from, item.to),
    );
    if (picked == null || !mounted) return null;
    if (!aiSummaryRangeWithinLimit(picked)) {
      showDunesToast(context, '时间跨度不能超过 31 天', kind: DunesToastKind.error);
      return null;
    }
    return picked;
  }

  List<int> get _currentConversationIds =>
      _participantConversations.map((c) => c.id).toList(growable: false);

  Future<void> _pickConversations() async {
    final item = _item;
    if (item == null || item.isGenerating) return;
    final result = await showConversationMultiPickerSheet(
      context: context,
      service: _conversations,
      title: '选择聊天（可多选）',
      multiSelect: true,
      initialSelected: _currentConversationIds.toSet(),
      maxCount: 20,
    );
    if (result == null || !mounted) return;
    final list = await resolveAiSummaryConversations(
      service: _conversations,
      conversationIds: result.toList(growable: false),
    );
    if (!mounted) return;
    setState(() => _participantConversations = list);
  }

  Future<void> _confirmRefresh() async {
    final item = _item;
    if (item == null || item.isGenerating || _refreshing) return;
    final nextIds = _currentConversationIds;
    if (nextIds.isEmpty) {
      showDunesToast(context, '请至少保留一个会话', kind: DunesToastKind.error);
      return;
    }
    final range = await _pickRangeForRegenerate(item);
    if (range == null || !mounted) return;
    final confirmed = await confirmAiSummaryAction(
      context: context,
      title: '重新生成',
      message:
          '将按 ${nextIds.length} 个会话、周期 ${aiSummaryRangeLabel(range)} 重新生成总结，确认继续？',
      confirmLabel: '重新生成',
    );
    if (!confirmed || !mounted) return;
    final apiRange = AiSummaryService.inclusiveDayRange(range.start, range.end);
    await _refresh(
      conversationIds: nextIds,
      from: apiRange.$1,
      to: apiRange.$2,
    );
  }

  Future<void> _refresh({
    List<int>? conversationIds,
    DateTime? from,
    DateTime? to,
  }) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final item = await _service.refresh(
        widget.summaryId,
        conversationIds: conversationIds,
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() => _item = item);
      _syncPoll(item);
      unawaited(_hydrateParticipants(item));
      showDunesToast(context, '已重新开始生成');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '重新生成失败'),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openParticipantsSheet() async {
    final canEdit = _item != null && !_item!.isGenerating;
    await showAiSummaryParticipantsSheet(
      context: context,
      service: _conversations,
      conversations: _participantConversations,
      title: '参与会话',
      editable: canEdit,
      onAdd: canEdit ? _pickConversations : null,
      onConversationsChanged: canEdit
          ? (next) {
              setState(() => _participantConversations = next);
            }
          : null,
    );
  }

  bool get _canRegenerate =>
      !_refreshing &&
      _item != null &&
      !_item!.isGenerating &&
      _participantConversations.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: Text(
          item?.theme.isNotEmpty == true ? item!.theme : '智能总结',
          style: DunesTypography.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (item != null && !item.isGenerating)
            TextButton(
              onPressed: _canRegenerate ? _confirmRefresh : null,
              child: Text(
                _refreshing
                    ? '提交中…'
                    : (_participantConversations.isEmpty
                        ? '请先选择会话'
                        : '重新生成'),
              ),
            ),
        ],
      ),
      body: _buildBody(item),
    );
  }

  Widget _buildParticipantsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiSummaryParticipantsRow(
            conversations: _participantConversations,
            service: _conversations,
            onTap: _openParticipantsSheet,
            dense: true,
          ),
          if (_item != null && !_item!.isGenerating)
            TextButton.icon(
              onPressed: _pickConversations,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('添加会话'),
              style: TextButton.styleFrom(
                foregroundColor: DunesColors.brandPurple,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(AiSummaryItem? item) {
    if (_loading && item == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && item == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: DunesTypography.sans(color: DunesColors.text3)),
            TextButton(onPressed: () => _load(), child: const Text('重试')),
          ],
        ),
      );
    }
    if (item == null) {
      return const Center(child: Text('总结不存在'));
    }

    if (item.isGenerating) {
      return Column(
        children: [
          _buildParticipantsHeader(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.statusLabel,
                    style: DunesTypography.sans(
                      fontSize: 15,
                      color: DunesColors.brandPurple,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '可离开此页，完成后会在会话列表提醒',
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (item.isFailed) {
      return Column(
        children: [
          _buildParticipantsHeader(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.errorMessage?.trim().isNotEmpty == true
                          ? item.errorMessage!
                          : '生成失败',
                      textAlign: TextAlign.center,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        color: DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _canRegenerate ? _confirmRefresh : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: DunesColors.brandPurple,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                      ),
                      child: Text(
                        _participantConversations.isEmpty
                            ? '请先选择会话'
                            : '重新生成',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final md = (item.resultMarkdown ?? '').trim();
    return Column(
      children: [
        _buildParticipantsHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                if (item.truncated || item.chunked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '依据部分聊天记录生成（内容较长已截断/分块）',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                  ),
                if (md.isEmpty)
                  Text(
                    item.summaryPreview ?? '暂无内容',
                    style: DunesTypography.sans(fontSize: 14, height: 1.7),
                  )
                else
                  MeetingMinutesMarkdown(markdown: md),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
