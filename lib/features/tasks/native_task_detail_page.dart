import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_ai_analysis.dart';
import 'task_api.dart';
import 'task_attachment_tile.dart';
import 'task_avatar.dart';
import 'task_link_section.dart';
import 'task_models.dart';
import 'task_postpone_dialog.dart';
import 'task_widgets.dart';

const _themePurple = Color(0xFF7B5CD8);

/// 工作台内嵌任务详情。
class NativeTaskDetailView extends StatefulWidget {
  const NativeTaskDetailView({
    super.key,
    required this.session,
    required this.taskId,
    required this.onBack,
    this.backLabel = '任务',
    this.viewerHint,
    this.onAddSubtask,
    this.onOpenTask,
    this.onOpenProgress,
    this.onOpenEvaluate,
    this.onTaskLoaded,
  });

  final AuthSession session;
  final int taskId;
  final VoidCallback onBack;
  /// 返回条文案，汇总入口用「任务汇总」。
  final String backLabel;
  /// 只读提示；为空时用默认句。
  final String? viewerHint;
  final VoidCallback? onAddSubtask;
  final ValueChanged<int>? onOpenTask;
  final ValueChanged<TaskItem>? onOpenProgress;
  final ValueChanged<TaskItem>? onOpenEvaluate;
  final ValueChanged<TaskItem>? onTaskLoaded;

  @override
  State<NativeTaskDetailView> createState() => _NativeTaskDetailViewState();
}

class _NativeTaskDetailViewState extends State<NativeTaskDetailView> {
  late final TaskApi _api = TaskApi(widget.session);
  TaskDetail? _detail;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _analysisRunning = false;
  Timer? _analysisTimer;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant NativeTaskDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) _reload();
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.getDetail(widget.taskId);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
        _analysisRunning = d.task.aiState == 'analyzing';
      });
      _scheduleAnalysisPoll();
      widget.onTaskLoaded?.call(d.task);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 分析进行中时轻量轮询状态，结束后按钮恢复为「AI 分析」。
  void _scheduleAnalysisPoll() {
    _analysisTimer?.cancel();
    if (!_analysisRunning) return;
    _analysisTimer = Timer(const Duration(seconds: 5), _refreshAnalysisRunning);
  }

  Future<void> _refreshAnalysisRunning() async {
    final t = _detail?.task;
    if (!mounted || t == null || !t.isMain || t.isPending) return;
    try {
      final items = await TaskAnalysisApi(widget.session).list(t.id);
      if (!mounted) return;
      setState(() {
        _analysisRunning = items.any((e) => e.isRunning && !e.isStale);
      });
    } catch (_) {}
    _scheduleAnalysisPoll();
  }

  /// 负责人 / 创建人 / 协同 / 审核人；否则仅可浏览。
  bool get _isStakeholder {
    final t = _detail?.task;
    if (t == null) return false;
    final uid = widget.session.userId;
    return t.ownerUserId == uid ||
        t.creatorUserId == uid ||
        t.approverUserId == uid ||
        t.coOwnerUserIds.contains(uid);
  }

  bool get _viewOnly => !_isStakeholder;

  bool get _canEditProgress {
    if (_viewOnly) return false;
    final t = _detail?.task;
    if (t == null) return false;
    final uid = widget.session.userId;
    return t.ownerUserId == uid || t.coOwnerUserIds.contains(uid);
  }

  bool get _canDelete {
    if (_viewOnly) return false;
    final t = _detail?.task;
    if (t == null) return false;
    final uid = widget.session.userId;
    return t.ownerUserId == uid || t.creatorUserId == uid;
  }

  bool get _canAddSubtask {
    if (_viewOnly) return false;
    final t = _detail?.task;
    if (t == null || !t.isMain) return false;
    final uid = widget.session.userId;
    return t.ownerUserId == uid ||
        t.creatorUserId == uid ||
        t.coOwnerUserIds.contains(uid);
  }

  /// 关联的增删只放给能编辑任务的人（负责人/创建人/协同），与后端一致；审核人仅可查看。
  bool get _canEditLinks {
    final t = _detail?.task;
    if (t == null) return false;
    final uid = widget.session.userId;
    return t.ownerUserId == uid ||
        t.creatorUserId == uid ||
        t.coOwnerUserIds.contains(uid);
  }

  bool get _canEvaluate {
    if (_viewOnly) return false;
    final t = _detail?.task;
    if (t == null) return false;
    if (t.isPending || t.status == 'cancelled' || t.status == 'rejected') {
      return false;
    }
    final uid = widget.session.userId;
    return t.creatorUserId == uid || t.approverUserId == uid;
  }

  void _openProgress() {
    final task = _detail?.task;
    if (task == null) return;
    if (task.isMain && (_detail?.subtasks.isNotEmpty ?? false)) {
      showDunesCenterToast(context, '进度由事项自动汇总');
      return;
    }
    widget.onOpenProgress?.call(task);
  }

  Future<void> _approve({required bool pass}) async {
    final task = _detail?.task;
    if (task == null) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(pass ? '通过事项' : '驳回事项'),
        content: TextField(controller: ctrl, decoration: _softDecoration('意见')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _themePurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(pass ? '通过' : '驳回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      if (pass) {
        await _api.approve(task.id, comment: ctrl.text.trim());
      } else {
        await _api.reject(task.id, comment: ctrl.text.trim());
      }
      widget.onBack();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final task = _detail?.task;
    if (task == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除任务'),
        content: Text('确认删除「${task.title}」？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.deleteTask(task.id);
      if (!mounted) return;
      showDunesCenterToast(context, '已删除');
      widget.onBack();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canPostpone {
    if (_viewOnly || widget.viewerHint != null) return false;
    final t = _detail?.task;
    if (t == null) return false;
    if (t.isPending ||
        t.status == 'completed' ||
        t.status == 'cancelled' ||
        t.status == 'rejected') {
      return false;
    }
    final uid = widget.session.userId;
    return t.ownerUserId == uid ||
        t.creatorUserId == uid ||
        t.coOwnerUserIds.contains(uid);
  }

  Future<void> _postpone() async {
    final task = _detail?.task;
    if (task == null || _busy) return;
    final draft = await showTaskPostponeDialog(context, task: task);
    if (draft == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final due = DateTime(
        draft.dueAt.year,
        draft.dueAt.month,
        draft.dueAt.day,
        23,
        59,
        59,
      );
      await _api.patchTask(task.id, {
        'dueAt': due.toUtc().toIso8601String(),
        if (draft.reason.isNotEmpty) 'progressNote': draft.reason,
      });
      await _reload();
      if (mounted) showDunesCenterToast(context, '已延期');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openEvaluate() {
    final task = _detail?.task;
    if (task == null) return;
    widget.onOpenEvaluate?.call(task);
  }

  Future<void> _deleteProgressLog(TaskProgressLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除进展记录'),
        content: const Text('确认删除这条进展记录？相关附件也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.deleteProgressLog(widget.taskId, log.id);
      await _reload();
      if (mounted) showDunesCenterToast(context, '已删除');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteEvalLog(TaskEvalLog log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除评价记录'),
        content: const Text('确认删除这条评价记录？相关附件也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.deleteEvalLog(widget.taskId, log.id);
      await _reload();
      if (mounted) showDunesCenterToast(context, '已删除');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fmtDateTime(DateTime d) {
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$m-$day $h:$min';
  }

  /// 主任务详情：主任务+子任务一起显示；子任务详情：只看自己。
  List<TaskProgressLog> _visibleProgressLogs(TaskDetail d) {
    if (d.task.isMain) return d.logs;
    return d.logs.where((l) => l.taskId == d.task.id).toList(growable: false);
  }

  List<TaskEvalLog> _visibleEvalLogs(TaskDetail d) {
    if (d.task.isMain) return d.evalLogs;
    return d.evalLogs
        .where((l) => l.taskId == d.task.id)
        .toList(growable: false);
  }

  String _activityKind(TaskDetail d, int logTaskId, bool isSubtask) {
    if (!d.task.isMain) return '事项';
    if (isSubtask || logTaskId != d.task.id) return '事项';
    return '一组事';
  }

  InputDecoration _softDecoration(String hint) {
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

  Widget _metaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTaskRange(DateTime? start, DateTime? due) {
    String fmt(DateTime d) {
      final local = d.toLocal();
      final m = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      return '${local.year}-$m-$day';
    }

    if (start != null && due != null) return '${fmt(start)} ~ ${fmt(due)}';
    if (start != null) return '开始 ${fmt(start)}';
    if (due != null) return '截止 ${fmt(due)}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      // 点击输入框外的空白处收起软键盘（详情页含描述内联编辑）
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: _buildContent(d),
      ),
    );
  }

  Widget _buildContent(TaskDetail? d) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: _themePurple))
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: widget.onBack, child: const Text('返回')),
              ],
            ),
          )
        : d == null
        ? const SizedBox.shrink()
        : RefreshIndicator(
            onRefresh: _reload,
            color: _themePurple,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onBack,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_back_ios_new,
                              size: 14,
                              color: DunesColors.text2,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              widget.backLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                color: DunesColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '任务详情',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _themePurple,
                        ),
                      ),
                    ),
                    if (_canAddSubtask)
                      TextButton.icon(
                        onPressed: _busy ? null : widget.onAddSubtask,
                        icon: const Icon(Icons.add_task_outlined, size: 18),
                        label: const Text('添加事项'),
                      ),
                    if (_canDelete)
                      IconButton(
                        tooltip: '删除',
                        onPressed: _busy ? null : _delete,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
                if (_viewOnly) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _themePurple.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.viewerHint ??
                          '只读：可查看任务信息，不可编辑或操作',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Builder(
                  builder: (_) {
                    final done = d.task.status == 'completed';
                    final overdueOpen = d.task.overdue && !done;
                    final overdueHint = taskUnfinishedOverdueHint(
                      overdue: d.task.overdue,
                      completed: done,
                      progressPct: d.task.progressPct,
                    );
                    return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EAED)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          buildTaskUserAvatar(
                            session: widget.session,
                            name: d.task.ownerName.isNotEmpty
                                ? d.task.ownerName
                                : d.task.title,
                            userId: d.task.ownerUserId,
                            avatarPreset: d.task.ownerAvatarPreset,
                            avatarObjectKey: d.task.ownerAvatarObjectKey,
                            avatarUrl: d.task.ownerAvatarUrl,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              d.task.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!d.task.isMain &&
                          d.task.parentTitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: d.task.parentId == null
                              ? null
                              : () => widget.onOpenTask?.call(d.task.parentId!),
                          child: Text(
                            '属于 ${d.task.parentTitle}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _themePurple,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          TaskMetaChip(
                            text: d.task.isMain ? '主任务' : '事项',
                            color: d.task.isMain
                                ? _themePurple
                                : const Color(0xFF2D8A5E),
                          ),
                          TaskMetaChip(
                            text: overdueOpen
                                ? '已逾期未办结'
                                : taskStatusLabel(d.task.status),
                            color: overdueOpen
                                ? const Color(0xFFB45309)
                                : (done
                                    ? const Color(0xFF1F9D76)
                                    : _themePurple),
                          ),
                          TaskMetaChip(
                            text: '优先级${taskPriorityLabel(d.task.priority)}',
                            color: DunesColors.text2,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _metaLine(
                        '负责人',
                        d.task.ownerName.isEmpty ? '未指定' : d.task.ownerName,
                      ),
                      if (d.task.startAt != null || d.task.dueAt != null)
                        _metaLine(
                          '任务周期',
                          _formatTaskRange(d.task.startAt, d.task.dueAt),
                        ),
                      if (d.task.sourceMeetingTitle.trim().isNotEmpty)
                        _metaLine(
                          '来源',
                          '会议《${d.task.sourceMeetingTitle.trim()}》',
                        ),
                      _metaLine(
                        '填报进度',
                        '${d.task.progressPct}%${done ? ' · 已办结' : ''}',
                      ),
                      const SizedBox(height: 8),
                      TaskProgressBar(
                        progressPct: d.task.progressPct,
                        overdue: overdueOpen,
                        completed: done,
                        height: 10,
                        showLabel: false,
                      ),
                      if (overdueHint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          overdueHint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB45309),
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (taskDistinctDescription(d.task).isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          taskDistinctDescription(d.task),
                          style: const TextStyle(fontSize: 14, height: 1.45),
                        ),
                      ],
                      if (d.task.acceptanceCriteria.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          '验收标准',
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.text3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.task.acceptanceCriteria.trim(),
                          style: const TextStyle(fontSize: 14, height: 1.45),
                        ),
                      ],
                    ],
                  ),
                );
                  },
                ),
                if (d.task.isPending &&
                    d.task.approverUserId == widget.session.userId) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _approve(pass: false),
                          child: const Text('驳回'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _themePurple,
                          ),
                          onPressed: _busy ? null : () => _approve(pass: true),
                          child: const Text('通过'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!d.task.isPending && _canEditProgress) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openProgress,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      d.task.isMain && d.subtasks.isNotEmpty
                          ? '进度由事项汇总'
                          : '更新进度',
                    ),
                  ),
                ],
                if (_canPostpone) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _postpone,
                    icon: const Icon(Icons.event_repeat, size: 18),
                    label: const Text('延期'),
                  ),
                ],
                if (_canEvaluate) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openEvaluate,
                    icon: const Icon(Icons.rate_review_outlined, size: 18),
                    label: Text(d.task.hasEval ? '修改评价' : '任务评价'),
                  ),
                ],
                if (d.task.isMain &&
                    d.subtasks.isNotEmpty &&
                    !d.task.isPending) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _themePurple,
                      side: BorderSide(
                        color: _themePurple.withValues(alpha: 0.45),
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () async {
                            await showTaskAiAnalysis(
                              context: context,
                              session: widget.session,
                              task: d.task,
                            );
                            unawaited(_refreshAnalysisRunning());
                          },
                    icon: _analysisRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _themePurple,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_analysisRunning ? 'AI 分析中，点击查看' : 'AI 分析'),
                  ),
                ],
                if (d.task.isMain && d.subtasks.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '事项填报进度',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TaskMemberProgressChart(
                    bars: buildTaskProgressBars(d),
                    onBarTap: (id) => widget.onOpenTask?.call(id),
                  ),
                ],
                if (d.attachments.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '附件',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final a in d.attachments)
                    TaskAttachmentTile(session: widget.session, attachment: a),
                ],
                if (d.task.isMain && !d.task.isPending) ...[
                  const SizedBox(height: 18),
                  TaskLinkSection(
                    session: widget.session,
                    task: d.task,
                    canEdit: _canEditLinks && !_busy,
                    onTaskChanged: _reload,
                  ),
                ],
                if (d.task.isMain) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '拆分事项',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '这些事项的进度会汇总到上面的主任务',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                  const SizedBox(height: 8),
                  if (d.subtasks.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE8EAED)),
                      ),
                      child: Text(
                        _canAddSubtask ? '还没有拆分事项，可点右上角添加' : '还没有拆分事项',
                        style: const TextStyle(color: DunesColors.text3),
                      ),
                    )
                  else
                    ...d.subtasks.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TaskWorkbenchCard(
                          task: s,
                          onTap: () => widget.onOpenTask?.call(s.id),
                          onProgress: s.isPending
                              ? null
                              : () => widget.onOpenProgress?.call(s),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                Text(
                  d.task.isMain ? '最近进展' : '最近进展',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_visibleProgressLogs(d).isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8EAED)),
                    ),
                    child: const Text(
                      '暂无进展记录',
                      style: TextStyle(color: DunesColors.text3),
                    ),
                  )
                else
                  for (final log in _visibleProgressLogs(d))
                    _ActivityCard(
                      title:
                          '${log.progressPct}%'
                          '${log.note.isEmpty ? '' : ' · ${log.note}'}',
                      taskKind: _activityKind(d, log.taskId, log.isSubtask),
                      taskTitle: log.taskTitle.isNotEmpty
                          ? log.taskTitle
                          : (log.taskId == d.task.id ? d.task.title : '任务'),
                      userName: log.userName.isEmpty ? '未知用户' : log.userName,
                      timeText: _fmtDateTime(log.createdAt),
                      attachments: log.attachments,
                      session: widget.session,
                      canDelete: !_viewOnly && log.canDelete && !_busy,
                      onDelete: () => _deleteProgressLog(log),
                    ),
                const SizedBox(height: 18),
                Text(
                  d.task.isMain ? '评价' : '评价',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (_visibleEvalLogs(d).isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8EAED)),
                    ),
                    child: const Text(
                      '暂无评价记录',
                      style: TextStyle(color: DunesColors.text3),
                    ),
                  )
                else
                  for (final log in _visibleEvalLogs(d))
                    _ActivityCard(
                      // 历史记录仍可能带 S/A/B/C 等级，保留展示
                      title:
                          '评价${log.level.trim().isEmpty ? '' : ' ${log.level}'}'
                          '${log.comment.isEmpty ? '' : '\n${log.comment}'}',
                      taskKind: _activityKind(d, log.taskId, log.isSubtask),
                      taskTitle: log.taskTitle.isNotEmpty
                          ? log.taskTitle
                          : (log.taskId == d.task.id ? d.task.title : '任务'),
                      userName: log.userName.isEmpty ? '未知用户' : log.userName,
                      timeText: _fmtDateTime(log.createdAt),
                      attachments: log.attachments,
                      session: widget.session,
                      canDelete: !_viewOnly && log.canDelete && !_busy,
                      onDelete: () => _deleteEvalLog(log),
                    ),
              ],
            ),
          );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.title,
    required this.taskKind,
    required this.taskTitle,
    required this.userName,
    required this.timeText,
    required this.attachments,
    required this.session,
    required this.canDelete,
    required this.onDelete,
  });

  final String title;
  final String taskKind;
  final String taskTitle;
  final String userName;
  final String timeText;
  final List<TaskAttachment> attachments;
  final AuthSession session;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kindColor = taskKind == '事项'
        ? const Color(0xFF2D8A5E)
        : _themePurple;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kindColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    taskKind,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kindColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    taskTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                if (canDelete)
                  IconButton(
                    tooltip: '删除',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                color: DunesColors.text,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$userName · $timeText',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final a in attachments)
                TaskAttachmentTile(session: session, attachment: a),
            ],
          ],
        ),
      ),
    );
  }
}
