import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';

class UrgeSuggestTarget {
  const UrgeSuggestTarget({
    required this.userId,
    required this.displayName,
  });

  final int userId;
  final String displayName;
}

/// 催办：选择接收人，统一发送审批名片 + 话术。
Future<bool> showApprovalUrgeSendSheet({
  required BuildContext context,
  required AuthSession session,
  required ApprovalChatShare share,
  required String draft,
  List<UrgeSuggestTarget> suggestTargets = const [],
  int? sourceMessageId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _UrgeSendSheet(
      session: session,
      share: share,
      initialDraft: draft,
      suggestTargets: suggestTargets,
      sourceMessageId: sourceMessageId,
    ),
  );
  return result == true;
}

class _UrgeSendSheet extends StatefulWidget {
  const _UrgeSendSheet({
    required this.session,
    required this.share,
    required this.initialDraft,
    required this.suggestTargets,
    this.sourceMessageId,
  });

  final AuthSession session;
  final ApprovalChatShare share;
  final String initialDraft;
  final List<UrgeSuggestTarget> suggestTargets;
  final int? sourceMessageId;

  @override
  State<_UrgeSendSheet> createState() => _UrgeSendSheetState();
}

class _UrgeSendSheetState extends State<_UrgeSendSheet> {
  late final TextEditingController _draft;
  late final ConversationService _im;
  late final XflowService _xflow;

  final Map<int, String> _people = {};
  final Set<int> _selectedUserIds = {};
  final Set<int> _extraConversationIds = {};
  bool _includeCard = true;
  bool _loadingTargets = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _draft = TextEditingController(text: widget.initialDraft);
    _im = ConversationService(session: widget.session);
    _xflow = XflowService(session: widget.session);
    for (final t in widget.suggestTargets) {
      if (t.userId <= 0) continue;
      _people[t.userId] = t.displayName;
      _selectedUserIds.add(t.userId);
    }
    _bootstrapTargets();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _bootstrapTargets() async {
    try {
      // 始终用轨迹补全：并发审批时可能有多名当前审批人。
      final trail = await _xflow.fetchSubmissionTrail(
        businessType: widget.share.businessType,
        businessId: widget.share.businessId,
      );
      if (trail != null) {
        final currentNos = trail.currentSteps.toSet();
        for (final step in trail.steps) {
          if (step.assigneeId <= 0) continue;
          final pending = step.decision.trim().isEmpty;
          if (!pending) continue;
          final inCurrentList = currentNos.contains(step.stepNo);
          final current = step.isCurrent == true ||
              inCurrentList ||
              (trail.isParallel && pending);
          if (!current) continue;
          final name = step.assigneeName.trim().isEmpty
              ? '审批人'
              : step.assigneeName.trim();
          final existed = _people.containsKey(step.assigneeId);
          _people[step.assigneeId] = name;
          // 新发现的当前审批人默认勾选；已有建议目标保持原勾选状态。
          if (!existed) _selectedUserIds.add(step.assigneeId);
        }
      }
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Future<void> _addConversations() async {
    final picked = await showConversationMultiPickerSheet(
      context: context,
      service: _im,
      title: '追加会话',
      multiSelect: true,
      initialSelected: _extraConversationIds,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _extraConversationIds
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _send() async {
    final draft = _draft.text.trim();
    if (draft.isEmpty) {
      showDunesToast(context, '请填写催办内容', kind: DunesToastKind.error);
      return;
    }
    if (_selectedUserIds.isEmpty && _extraConversationIds.isEmpty) {
      showDunesToast(context, '请至少选择一位接收人或会话', kind: DunesToastKind.error);
      return;
    }
    setState(() => _sending = true);
    try {
      final data = await _im.approvalAssistantUrgeSend(
        businessType: widget.share.businessType,
        businessId: widget.share.businessId,
        draft: draft,
        recipientUserIds: _selectedUserIds.toList(),
        conversationIds: _extraConversationIds.toList(),
        includeApprovalCard: _includeCard,
        sourceMessageId: widget.sourceMessageId,
        card: widget.share,
      );
      if (!mounted) return;
      final sent = (data['sentCount'] as num?)?.toInt() ?? 0;
      final failed = (data['failedCount'] as num?)?.toInt() ?? 0;
      if (sent <= 0) {
        showDunesToast(
          context,
          failed > 0 ? '发送失败，请稍后重试' : '未发送任何会话',
          kind: DunesToastKind.error,
        );
        return;
      }
      showDunesToast(
        context,
        failed > 0 ? '已发送 $sent 个会话，失败 $failed' : '已统一发送审批名片和催办内容',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e),
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '发送催办',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '将统一发送：${_includeCard ? '审批名片 + ' : ''}催办话术',
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Text(
                      '催办内容',
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _draft,
                      maxLines: 4,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        color: DunesColors.text,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: DunesColors.brandPurpleSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _includeCard,
                      activeColor: DunesColors.brandPurple,
                      title: Text(
                        '同时发送审批名片',
                        style: DunesTypography.sans(
                          fontSize: 13.5,
                          color: DunesColors.text,
                        ),
                      ),
                      onChanged: _sending
                          ? null
                          : (v) => setState(() => _includeCard = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '当前审批人（可多选）',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.text2,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _sending ? null : _addConversations,
                          child: Text(
                            _extraConversationIds.isEmpty
                                ? '追加会话'
                                : '已选会话 ${_extraConversationIds.length}',
                          ),
                        ),
                      ],
                    ),
                    if (_loadingTargets)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_people.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '未找到当前审批人，可点「追加会话」选择私聊/群聊发送',
                          style: DunesTypography.sans(
                            fontSize: 12.5,
                            color: DunesColors.text3,
                          ),
                        ),
                      )
                    else
                      ..._people.entries.map((e) {
                        final selected = _selectedUserIds.contains(e.key);
                        return CheckboxListTile(
                          value: selected,
                          contentPadding: EdgeInsets.zero,
                          activeColor: DunesColors.brandPurple,
                          controlAffinity: ListTileControlAffinity.trailing,
                          title: Text(
                            e.value,
                            style: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text,
                            ),
                          ),
                          onChanged: _sending
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedUserIds.add(e.key);
                                    } else {
                                      _selectedUserIds.remove(e.key);
                                    }
                                  });
                                },
                        );
                      }),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.brandPurple,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '确认发送',
                          style: DunesTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
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
