import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../meeting/meeting_task_create_dialog.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../shell/dunes_toast.dart';
import '../tasks/task_link_api.dart';
import '../tasks/task_link_models.dart';
import 'meeting_suggestion_snooze.dart';

/// 任务助手里的会议任务建议包：创建 / 稍后提醒 / 不相关，并可打开会议纪要。
class MeetingSuggestionImCard extends StatefulWidget {
  const MeetingSuggestionImCard({
    super.key,
    required this.session,
    required this.meetingId,
    required this.meetingTitle,
    this.snapshot = const [],
    this.onOpenMeeting,
  });

  final AuthSession session;
  final int meetingId;
  final String meetingTitle;
  final List<MeetingTaskSuggestion> snapshot;
  final Future<void> Function()? onOpenMeeting;

  @override
  State<MeetingSuggestionImCard> createState() => _MeetingSuggestionImCardState();
}

class _MeetingSuggestionImCardState extends State<MeetingSuggestionImCard> {
  late final TaskLinkApi _api = TaskLinkApi(widget.session);
  List<MeetingTaskSuggestion> _items = const [];
  final Map<int, DateTime> _snoozedUntil = {};
  bool _busy = false;
  bool _expanded = false;

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

  Future<void> _openMinutes() async {
    if (widget.onOpenMeeting != null) {
      await widget.onOpenMeeting!();
    } else {
      await showNativeMeetingDetail(
        context: context,
        session: widget.session,
        meetingId: widget.meetingId,
      );
    }
    if (mounted) unawaited(_refresh());
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
      if (mounted) {
        showDunesCenterToast(
          context,
          friendlyErrorText(e, fallback: '创建失败'),
        );
      }
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
      if (mounted) {
        showDunesCenterToast(
          context,
          friendlyErrorText(e, fallback: '操作失败'),
        );
      }
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
      if (mounted) {
        showDunesCenterToast(
          context,
          friendlyErrorText(e, fallback: '全部创建失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, DateTime)?> _pickSnooze() {
    return showModalBottomSheet<(String, DateTime)>(
      context: context,
      backgroundColor: DunesColors.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '延迟通知',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  '到点后任务助手会再提醒一次，建议先不处理。',
                  style: TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
                const SizedBox(height: 12),
                for (final preset in const ['2h', 'tomorrow9', '3d9'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(
                          ctx,
                          (preset, meetingSuggestionRemindAt(preset)),
                        );
                      },
                      child: Text(meetingSnoozePresetLabel(preset)),
                    ),
                  ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked == null || !ctx.mounted) return;
                    Navigator.pop(
                      ctx,
                      (
                        'custom',
                        DateTime(picked.year, picked.month, picked.day, 9),
                      ),
                    );
                  },
                  child: const Text('自定义日期（当天 9:00）'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _snoozeOne(MeetingTaskSuggestion s) async {
    final picked = await _pickSnooze();
    if (picked == null || !mounted) return;
    await _snoozeItems([s], picked.$1, picked.$2);
  }

  Future<void> _snoozeAll() async {
    if (_items.isEmpty) return;
    final picked = await _pickSnooze();
    if (picked == null || !mounted) return;
    await _snoozeItems(_items, picked.$1, picked.$2);
  }

  Future<void> _snoozeItems(
    List<MeetingTaskSuggestion> items,
    String preset,
    DateTime remindAt,
  ) async {
    setState(() => _busy = true);
    try {
      for (final s in List<MeetingTaskSuggestion>.from(items)) {
        await _api.snoozeSuggestion(
          widget.meetingId,
          s.id,
          remindAt: remindAt,
          preset: preset,
        );
        _snoozedUntil[s.id] = remindAt;
      }
      if (!mounted) return;
      showDunesCenterToast(
        context,
        '将在 ${formatMeetingSnoozeAt(remindAt)} 再提醒',
      );
      setState(() {
        final ids = items.map((e) => e.id).toSet();
        _items = _items.where((e) => !ids.contains(e.id)).toList();
      });
      await _refresh();
    } catch (e) {
      if (mounted) {
        showDunesCenterToast(
          context,
          friendlyErrorText(e, fallback: '延迟通知失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vis = _expanded ? _items : _items.take(3).toList(growable: false);
    final extra = _items.length - vis.length;
    final body = <Widget>[
      _headerRow(),
      _meetingLink(),
      const SizedBox(height: 8),
      for (final s in vis) _itemCard(s),
      if (extra > 0)
        TextButton(
          onPressed: () => setState(() => _expanded = true),
          style: TextButton.styleFrom(
            foregroundColor: DunesColors.brandPurpleDeep,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          child: Text('还有 $extra 条，查看全部'),
        )
      else if (_expanded && _items.length > 3)
        TextButton(
          onPressed: () => setState(() => _expanded = false),
          style: TextButton.styleFrom(
            foregroundColor: DunesColors.text2,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          child: const Text('收起'),
        ),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        // 展开后不要内嵌 ListView：内外层抢滚动会让任务助手上滑卡住并闪。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: body,
        ),
      ),
    );
  }

  Widget _headerRow() {
    return Row(
      children: [
        const Icon(
          Icons.task_alt_outlined,
          size: 16,
          color: DunesColors.brandPurple,
        ),
        const SizedBox(width: 6),
        const Text(
          '任务建议',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        if (_items.isNotEmpty)
          TextButton(
            onPressed: _busy ? null : _snoozeAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('稍后提醒'),
          ),
        if (_items.length > 1)
          TextButton(
            onPressed: _busy ? null : _acceptAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('全部创建'),
          ),
      ],
    );
  }

  Widget _meetingLink() {
    return InkWell(
      onTap: _busy ? null : () => unawaited(_openMinutes()),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${widget.meetingTitle} · ${_items.length} 条待创建',
                style: const TextStyle(
                  fontSize: 11,
                  color: DunesColors.text2,
                ),
              ),
            ),
            const Text(
              '会议纪要',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DunesColors.brandPurpleDeep,
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: DunesColors.brandPurpleDeep,
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(MeetingTaskSuggestion s) {
    final snoozed = _snoozedUntil[s.id];
    return Container(
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
          if (snoozed != null)
            Text(
              '将在 ${formatMeetingSnoozeAt(snoozed)} 再提醒',
              style: const TextStyle(
                fontSize: 12,
                color: DunesColors.text2,
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DunesColors.brandPurple,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : () => _accept(s),
                  child: const Text('创建'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _snoozeOne(s),
                  child: const Text('稍后'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _dismiss(s),
                  child: const Text('不相关'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
