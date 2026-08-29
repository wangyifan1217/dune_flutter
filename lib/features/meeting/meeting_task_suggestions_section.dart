import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../kb/kb_document_coordinator.dart';
import '../shell/dunes_toast.dart';
import '../tasks/task_link_api.dart';
import '../tasks/task_link_models.dart';

/// 会议详情的「任务建议」区块：AI 分析状态、已同步任务、创建任务建议卡。
/// 数据按组织者过滤，非组织者拿到空数据时整块不渲染，零打扰。
class MeetingTaskSuggestionsSection extends StatefulWidget {
  const MeetingTaskSuggestionsSection({
    super.key,
    required this.session,
    required this.meetingId,
  });

  final AuthSession session;
  final int meetingId;

  @override
  State<MeetingTaskSuggestionsSection> createState() =>
      _MeetingTaskSuggestionsSectionState();
}

class _MeetingTaskSuggestionsSectionState
    extends State<MeetingTaskSuggestionsSection> {
  late final TaskLinkApi _api = TaskLinkApi(widget.session);
  MeetingTaskBindData _data = const MeetingTaskBindData();
  bool _loaded = false;
  bool _busy = false;
  Timer? _poll;
  final List<Timer> _delayed = [];

  @override
  void initState() {
    super.initState();
    _load();
    // 纪要入库知识库后 AI 分析随即开始，延迟补拉两次接住新状态。
    KbDocumentCoordinator.instance.addListener(_onKbChanged);
  }

  @override
  void didUpdateWidget(covariant MeetingTaskSuggestionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meetingId != widget.meetingId) {
      _data = const MeetingTaskBindData();
      _loaded = false;
      _load();
    }
  }

  @override
  void dispose() {
    KbDocumentCoordinator.instance.removeListener(_onKbChanged);
    _poll?.cancel();
    for (final t in _delayed) {
      t.cancel();
    }
    super.dispose();
  }

  void _onKbChanged() {
    for (final delay in const [Duration(seconds: 3), Duration(seconds: 10)]) {
      _delayed.add(
        Timer(delay, () {
          if (mounted) _load();
        }),
      );
    }
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchMeetingSuggestions(widget.meetingId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loaded = true;
      });
      _managePolling();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  void _managePolling() {
    final running = _data.bindRun?.isRunningFresh == true;
    if (running && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    } else if (!running && _poll != null) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _accept(
    MeetingTaskSuggestion sug, {
    String? title,
    String? description,
    bool silent = false,
  }) async {
    try {
      final task = await _api.acceptSuggestion(
        widget.meetingId,
        sug.id,
        title: title,
        description: description,
      );
      if (!mounted) return;
      if (!silent) {
        showDunesCenterToast(context, '已创建任务「${task.title}」');
      }
      await _load();
    } catch (e) {
      if (mounted && !silent) showDunesCenterToast(context, '$e');
    }
  }

  Future<void> _acceptAll() async {
    if (_busy) return;
    final all = List<MeetingTaskSuggestion>.from(_data.suggestions);
    final confirmed = await _confirmTaskAction(
      title: '确认全部创建任务',
      content: '将根据本次会议纪要创建 ${all.length} 个任务，创建后会同步到相关负责人的任务列表。',
      confirmLabel: '全部创建',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final sug in all) {
        await _accept(sug, silent: true);
      }
      if (mounted) {
        showDunesCenterToast(context, '已创建 ${all.length} 个任务');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss(MeetingTaskSuggestion sug) async {
    if (_busy) return;
    final confirmed = await _confirmTaskAction(
      title: '确认忽略任务建议',
      content: '“${sug.suggestedTitle}”将不再出现在本次会议的任务建议中。',
      confirmLabel: '确认忽略',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.dismissSuggestion(widget.meetingId, sug.id);
      if (!mounted) return;
      setState(() {
        _data = MeetingTaskBindData(
          suggestions: _data.suggestions
              .where((s) => s.id != sug.id)
              .toList(growable: false),
          syncedTasks: _data.syncedTasks,
          bindRun: _data.bindRun,
        );
      });
      showDunesCenterToast(context, '已忽略，之后不再提示');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAndAccept(MeetingTaskSuggestion sug) async {
    final titleCtrl = TextEditingController(text: sug.suggestedTitle);
    final descCtrl = TextEditingController(text: sug.suggestedDescription);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('创建任务'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: _dialogDecoration('任务标题'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 4,
                decoration: _dialogDecoration('任务描述'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DunesColors.brandPurple,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final confirmed = await _confirmTaskAction(
      title: '确认创建任务',
      content: '将创建任务“${titleCtrl.text.trim()}”，并同步到相关负责人的任务列表。',
      confirmLabel: '确认创建',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _accept(
        sug,
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dialogDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F6F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<bool> _confirmTaskAction({
    required String title,
    required String content,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: destructive
                      ? DunesColors.coral
                      : DunesColors.brandPurple,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final running = _data.bindRun?.isRunningFresh == true;
    if (!_loaded ||
        (_data.suggestions.isEmpty && _data.syncedTasks.isEmpty && !running)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.task_alt_outlined,
                size: 18,
                color: DunesColors.brandPurple,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '任务建议',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (_data.suggestions.length > 1)
                TextButton(
                  onPressed: _busy ? null : _acceptAll,
                  child: const Text('全部创建'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (running)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DunesColors.brandPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI 正在分析纪要，识别待办与相关任务…',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.brandPurpleDeep,
                    ),
                  ),
                ],
              ),
            ),
          if (_data.syncedTasks.isNotEmpty) ...[
            Text(
              '已同步到我的任务',
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 6),
            for (final t in _data.syncedTasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: DunesColors.readReceipt,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.text2,
                        ),
                      ),
                    ),
                    Text(
                      '${t.progressPct}%',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            if (_data.suggestions.isNotEmpty) const SizedBox(height: 8),
          ],
          for (final sug in _data.suggestions) _buildSuggestionCard(sug),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(MeetingTaskSuggestion sug) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sug.suggestedTitle,
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          if (sug.suggestedDescription.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sug.suggestedDescription,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.text2,
                height: 1.4,
              ),
            ),
          ],
          if (sug.decisionExcerpt.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '来源：${sug.decisionExcerpt}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
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
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final confirmed = await _confirmTaskAction(
                          title: '确认创建任务',
                          content:
                              '将创建任务“${sug.suggestedTitle}”，并同步到相关负责人的任务列表。',
                          confirmLabel: '确认创建',
                        );
                        if (!confirmed || !mounted) return;
                        setState(() => _busy = true);
                        try {
                          await _accept(sug);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('创建任务'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _busy ? null : () => _editAndAccept(sug),
                child: const Text('编辑'),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DunesColors.text3,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _busy ? null : () => _dismiss(sug),
                child: const Text('不相关'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
