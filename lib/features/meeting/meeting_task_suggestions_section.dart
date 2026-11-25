import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../kb/kb_document_coordinator.dart';
import '../shell/dunes_toast.dart';
import '../tasks/task_api.dart';
import '../tasks/task_link_api.dart';
import '../tasks/task_link_models.dart';
import '../tasks/task_models.dart';
import 'meeting_task_create_dialog.dart';

/// 会议详情的「任务建议」区块：AI 分析状态、已同步任务、创建任务建议卡。
/// 数据按组织者过滤，非组织者拿到空数据时整块不渲染，零打扰。
class MeetingTaskSuggestionsSection extends StatefulWidget {
  const MeetingTaskSuggestionsSection({
    super.key,
    required this.session,
    required this.meetingId,
    this.canLinkTasks = false,
  });

  final AuthSession session;
  final int meetingId;
  final bool canLinkTasks;

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
    final meetingId = widget.meetingId;
    try {
      final data = await _api.fetchMeetingSuggestions(meetingId);
      if (!mounted || widget.meetingId != meetingId) return;
      setState(() {
        _data = data;
        _loaded = true;
      });
      _managePolling();
    } catch (_) {
      if (!mounted || widget.meetingId != meetingId) return;
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

  Future<void> _linkExistingTask() async {
    if (_busy) return;
    final meetingId = widget.meetingId;
    final task = await showDialog<TaskItem>(
      context: context,
      builder: (_) => _MeetingTaskPicker(
        api: TaskApi(widget.session),
        linkedIds: _data.syncedTasks.map((task) => task.taskId).toSet(),
      ),
    );
    if (task == null || !mounted || widget.meetingId != meetingId || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.addLink(task.id, {'kind': 'meeting', 'meetingId': meetingId});
      if (!mounted || widget.meetingId != meetingId) return;
      showDunesCenterToast(context, '已关联任务「${task.title}」');
      await _load();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(
    MeetingTaskSuggestion sug, {
    String? title,
    String? description,
    String? acceptanceCriteria,
    int? ownerUserId,
    String? priority,
    required DateTime startAt,
    required DateTime dueAt,
    int? parentTaskId,
    bool silent = false,
  }) async {
    try {
      final task = await _api.acceptSuggestion(
        widget.meetingId,
        sug.id,
        title: title,
        description: description,
        acceptanceCriteria: acceptanceCriteria,
        ownerUserId: ownerUserId,
        priority: priority,
        startAt: startAt,
        dueAt: dueAt,
        parentTaskId: parentTaskId,
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
    final draft = await showMeetingTaskCreateDialog(
      context,
      session: widget.session,
      title: '全部创建任务',
      batchCount: all.length,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      for (final sug in all) {
        await _accept(
          sug,
          ownerUserId: draft.ownerUserId,
          priority: draft.priority,
          startAt: draft.startAt,
          dueAt: draft.dueAt,
          parentTaskId: draft.parentTaskId,
          silent: true,
        );
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

  Future<void> _createFromSuggestion(MeetingTaskSuggestion sug) async {
    final draft = await showMeetingTaskCreateDialog(
      context,
      session: widget.session,
      title: sug.suggestedTitle,
      description: sug.suggestedDescription,
      acceptanceCriteria: sug.decisionExcerpt,
    );
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _accept(
        sug,
        title: draft.title,
        description: draft.description,
        acceptanceCriteria: draft.acceptanceCriteria,
        ownerUserId: draft.ownerUserId,
        priority: draft.priority,
        startAt: draft.startAt,
        dueAt: draft.dueAt,
        parentTaskId: draft.parentTaskId,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      ? DunesColors.resolve(
                          ctx,
                          DunesColors.coral,
                          role: DunesColorRole.surface,
                        )
                      : DunesColors.resolve(
                          ctx,
                          DunesColors.brandPurple,
                          role: DunesColorRole.surface,
                        ),
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
        (!widget.canLinkTasks &&
            _data.suggestions.isEmpty &&
            _data.syncedTasks.isEmpty &&
            !running)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.task_alt_outlined,
                size: 18,
                color: DunesColors.resolve(context, DunesColors.brandPurple),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '会议任务',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
              ),
              if (_data.suggestions.length > 1)
                TextButton(
                  onPressed: _busy ? null : _acceptAll,
                  child: const Text('全部创建'),
                ),
              if (widget.canLinkTasks)
                TextButton(
                  onPressed: _busy ? null : _linkExistingTask,
                  child: const Text('关联任务'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_data.suggestions.isNotEmpty)
            Text(
              '处理也会出现在任务助手，不必回到这场会议。',
              style: DunesTypography.sans(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
          const SizedBox(height: 8),
          if (running)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI 正在分析纪要，识别待办与相关任务…',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleDeep,
                      ),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          if (_data.syncedTasks.isNotEmpty) ...[
            Text(
              '已关联任务',
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
            const SizedBox(height: 6),
            for (final t in _data.syncedTasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 15,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.readReceipt,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
                          context: context,
                        ),
                      ),
                    ),
                    Text(
                      '${t.progressPct}%',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text3),
                        context: context,
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
        color: DunesColors.resolve(
          context,
          DunesColors.bgSoft,
          role: DunesColorRole.surface,
        ),
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
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
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
                color: DunesColors.resolve(context, DunesColors.text2),
                height: 1.4,
                context: context,
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
                color: DunesColors.resolve(context, DunesColors.text3),
                context: context,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: DunesColors.resolve(
                    context,
                    DunesColors.brandPurple,
                    role: DunesColorRole.surface,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _busy ? null : () => _createFromSuggestion(sug),
                child: const Text('创建任务'),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: DunesColors.resolve(
                    context,
                    DunesColors.text3,
                  ),
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

class _MeetingTaskPicker extends StatefulWidget {
  const _MeetingTaskPicker({required this.api, required this.linkedIds});

  final TaskApi api;
  final Set<int> linkedIds;

  @override
  State<_MeetingTaskPicker> createState() => _MeetingTaskPickerState();
}

class _MeetingTaskPickerState extends State<_MeetingTaskPicker> {
  final _search = TextEditingController();
  int _page = 0;
  Timer? _debounce;
  late Future<TaskListPage> _results = _fetch();

  Future<TaskListPage> _fetch() => widget.api.listTasksPage(
    scope: 'editable_main',
    q: _search.text,
    page: _page,
  );

  void _loadPage(int page) {
    _debounce?.cancel();
    setState(() {
      _page = page;
      _results = _fetch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('关联已有任务'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索任务',
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => _loadPage(0),
                );
              },
              onSubmitted: (_) => _loadPage(0),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<TaskListPage>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton(
                        onPressed: () => _loadPage(_page),
                        child: const Text('加载失败，点击重试'),
                      ),
                    );
                  }
                  final results = snapshot.requireData;
                  return Column(
                    children: [
                      Expanded(
                        child: results.items.isEmpty
                            ? const Center(child: Text('暂无可关联任务'))
                            : ListView.builder(
                                key: ValueKey(_results),
                                itemCount: results.items.length,
                                itemBuilder: (context, index) {
                                  final task = results.items[index];
                                  final linked = widget.linkedIds.contains(
                                    task.id,
                                  );
                                  return ListTile(
                                    title: Text(task.title),
                                    trailing: linked
                                        ? const Text('已关联')
                                        : const Icon(Icons.add_link),
                                    enabled: !linked,
                                    onTap: linked
                                        ? null
                                        : () => Navigator.pop(context, task),
                                  );
                                },
                              ),
                      ),
                      if (_page > 0 || results.hasMore)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _page > 0
                                  ? () => _loadPage(_page - 1)
                                  : null,
                              child: const Text('上一页'),
                            ),
                            TextButton(
                              onPressed: results.hasMore
                                  ? () => _loadPage(_page + 1)
                                  : null,
                              child: const Text('下一页'),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
