import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../meeting/meeting_task_create_dialog.dart';
import '../shell/dunes_toast.dart';
import '../tasks/task_link_api.dart';
import '../tasks/task_link_models.dart';

/// 任务助手里的会议任务建议包：创建前需选择开始/结束时间。
class MeetingSuggestionImCard extends StatefulWidget {
  const MeetingSuggestionImCard({
    super.key,
    required this.session,
    required this.meetingId,
    required this.meetingTitle,
    this.snapshot = const [],
  });

  final AuthSession session;
  final int meetingId;
  final String meetingTitle;
  final List<MeetingTaskSuggestion> snapshot;

  @override
  State<MeetingSuggestionImCard> createState() => _MeetingSuggestionImCardState();
}

class _MeetingSuggestionImCardState extends State<MeetingSuggestionImCard> {
  late final TaskLinkApi _api = TaskLinkApi(widget.session);
  List<MeetingTaskSuggestion> _items = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = widget.snapshot;
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final data = await _api.fetchMeetingSuggestions(widget.meetingId);
      if (!mounted) return;
      setState(() => _items = data.suggestions);
    } catch (_) {}
  }

  Future<void> _accept(MeetingTaskSuggestion s) async {
    final draft = await showMeetingTaskCreateDialog(
      context,
      session: widget.session,
      title: s.suggestedTitle,
      description: s.suggestedDescription,
      acceptanceCriteria: s.decisionExcerpt,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final task = await _api.acceptSuggestion(
        widget.meetingId,
        s.id,
        title: draft.title,
        description: draft.description,
        acceptanceCriteria: draft.acceptanceCriteria,
        ownerUserId: draft.ownerUserId,
        priority: draft.priority,
        startAt: draft.startAt,
        dueAt: draft.dueAt,
      );
      if (!mounted) return;
      showDunesCenterToast(context, '已创建「${task.title}」');
      await _refresh();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss(MeetingTaskSuggestion s) async {
    setState(() => _busy = true);
    try {
      await _api.dismissSuggestion(widget.meetingId, s.id);
      if (!mounted) return;
      showDunesCenterToast(context, '已标记不相关');
      await _refresh();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptAll() async {
    final draft = await showMeetingTaskCreateDialog(
      context,
      session: widget.session,
      title: '全部创建任务',
      batchCount: _items.length,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final s in List<MeetingTaskSuggestion>.from(_items)) {
        await _api.acceptSuggestion(
          widget.meetingId,
          s.id,
          ownerUserId: draft.ownerUserId,
          priority: draft.priority,
          startAt: draft.startAt,
          dueAt: draft.dueAt,
        );
      }
      if (!mounted) return;
      showDunesCenterToast(context, '已全部创建');
      await _refresh();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vis = _items.take(3).toList(growable: false);
    final extra = _items.length - vis.length;
    return Container(
      width: 292,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.task_alt_outlined,
                size: 16,
                color: DunesColors.brandPurple,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '任务建议',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              if (_items.length > 1)
                TextButton(
                  onPressed: _busy ? null : _acceptAll,
                  child: const Text('全部创建'),
                ),
            ],
          ),
          Text(
            '${widget.meetingTitle} · ${_items.length} 条待创建',
            style: const TextStyle(fontSize: 11, color: DunesColors.text2),
          ),
          const SizedBox(height: 8),
          for (final s in vis)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.suggestedTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (s.decisionExcerpt.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '来源：${s.decisionExcerpt}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: DunesColors.brandPurple,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _busy ? null : () => _accept(s),
                        child: const Text('创建'),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _busy ? null : () => _dismiss(s),
                        child: const Text('不相关'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (extra > 0)
            Text(
              '还有 $extra 条，打开会议可查看全部',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.brandPurpleDeep,
              ),
            ),
        ],
      ),
    );
  }
}
