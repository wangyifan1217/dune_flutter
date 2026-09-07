import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../kpi/workbench_kpi_service.dart';
import '../shell/dunes_toast.dart';
import 'work_profile_kpi.dart';

const _perfAccent = Color(0xFF8C5A91);

String formatKpiAdj(double v) {
  final body = v.abs() == v.roundToDouble()
      ? v.abs().toInt().toString()
      : v.abs().toStringAsFixed(2);
  if (v > 0) return '+$body';
  if (v < 0) return '-$body';
  return '0';
}

String formatKpiNum(double? v) {
  if (v == null) return '—';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

String formatKpiMonth(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

String formatKpiMonthLabel(DateTime d) => '${d.year}年${d.month}月';

DateTime kpiMonthStart(DateTime d) => DateTime(d.year, d.month);

DateTime kpiShiftMonth(DateTime d, int delta) =>
    DateTime(d.year, d.month + delta);

DateTime parseKpiMonth(String raw, DateTime fallback) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return kpiMonthStart(fallback);
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// 绩效发展：查看当月计入任务与得分等级，并支持本人任务增删改（二次确认）。
/// 默认当月，可自选月份；未注入 [score] 时请求 `/kpi/my-score`。
class NativeWorkProfilePerfPage extends StatefulWidget {
  const NativeWorkProfilePerfPage({
    super.key,
    required this.session,
    required this.onBack,
    this.score,
    this.initialMonth,
    this.now,
    this.loadScore,
    this.listTasks,
    this.createTask,
    this.updateTask,
    this.deleteTask,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final WorkProfileKpiScore? score;
  final DateTime? initialMonth;
  final DateTime? now;
  final Future<WorkProfileKpiScore> Function(String month)? loadScore;
  final Future<List<WorkbenchKpiTask>> Function(String month)? listTasks;
  final Future<WorkbenchKpiTask> Function(WorkbenchKpiTask draft)? createTask;
  final Future<WorkbenchKpiTask> Function(WorkbenchKpiTask draft)? updateTask;
  final Future<void> Function(int id)? deleteTask;

  @override
  State<NativeWorkProfilePerfPage> createState() =>
      _NativeWorkProfilePerfPageState();
}

class _NativeWorkProfilePerfPageState extends State<NativeWorkProfilePerfPage> {
  late DateTime _month;
  WorkProfileKpiScore? _score;
  List<WorkbenchKpiTask> _tasks = const [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  int _loadGen = 0;

  DateTime get _clock => widget.now ?? DateTime.now();
  DateTime get _currentMonth => kpiMonthStart(_clock);
  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);
  bool get _manageTasks =>
      widget.listTasks != null ||
      (widget.score == null && widget.loadScore == null);

  @override
  void initState() {
    super.initState();
    final injected = widget.score?.month ?? '';
    _month = injected.isNotEmpty
        ? parseKpiMonth(injected, _currentMonth)
        : kpiMonthStart(widget.initialMonth ?? _currentMonth);
    _score = widget.score;
    if (widget.score != null) {
      _loading = false;
      if (_manageTasks) unawaited(_loadTasks());
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (widget.score != null) {
      if (_manageTasks) unawaited(_loadTasks());
      setState(() {});
      return;
    }
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final month = formatKpiMonth(_month);
      final scoreFut = widget.loadScore != null
          ? widget.loadScore!(month)
          : WorkProfileKpiService(
              session: widget.session,
            ).fetchMyScore(month: month);
      final tasksFut = _manageTasks
          ? _fetchTasks(month)
          : Future<List<WorkbenchKpiTask>>.value(const []);
      final score = await scoreFut;
      var tasks = const <WorkbenchKpiTask>[];
      if (_manageTasks) {
        try {
          tasks = await tasksFut;
        } catch (e) {
          if (mounted) {
            showDunesToast(
              context,
              friendlyErrorText(e, fallback: '任务加载失败'),
              kind: DunesToastKind.error,
            );
          }
        }
      }
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _score = score;
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e;
        _score = null;
        _loading = false;
      });
    }
  }

  Future<List<WorkbenchKpiTask>> _fetchTasks(String month) {
    if (widget.listTasks != null) return widget.listTasks!(month);
    return WorkbenchKpiService(
      session: widget.session,
    ).listMyTasks(countedOnly: true, month: month);
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await _fetchTasks(formatKpiMonth(_month));
      if (!mounted) return;
      setState(() => _tasks = tasks);
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '任务加载失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: _earliestMonth,
      lastDate: _currentMonth,
      helpText: '选择月份',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = kpiMonthStart(picked));
    unawaited(_load());
  }

  void _shiftMonth(int delta) {
    final next = kpiShiftMonth(_month, delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    setState(() => _month = next);
    unawaited(_load());
  }

  Future<bool> _confirm({
    required String title,
    String? content,
    String confirmLabel = '确认',
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: content == null || content.isEmpty ? null : Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('work-profile-perf-confirm-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: danger ? const Color(0xFFBC5C40) : _perfAccent,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editTask(WorkbenchKpiTask? existing) async {
    if (!_manageTasks || _busy) return;
    final draft = await showDialog<WorkbenchKpiTask>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PerfTaskEditorDialog(
        initial:
            existing ??
            WorkbenchKpiTask(
              id: 0,
              userId: widget.session.userId,
              userName: widget.session.displayName ?? '',
              name: '',
            ),
      ),
    );
    if (draft == null || !mounted) return;
    final creating = existing == null || existing.id <= 0;
    final ok = await _confirm(
      title: creating ? '确认新增任务？' : '确认保存修改？',
      content: creating ? '将新增计入任务「${draft.name}」。' : '将更新任务「${draft.name}」。',
      confirmLabel: creating ? '确认新增' : '确认保存',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      if (creating) {
        if (widget.createTask != null) {
          await widget.createTask!(draft);
        } else {
          await WorkbenchKpiService(
            session: widget.session,
          ).createMyTask(draft);
        }
        if (mounted) showDunesToast(context, '任务已新增');
      } else {
        if (widget.updateTask != null) {
          await widget.updateTask!(draft);
        } else {
          await WorkbenchKpiService(
            session: widget.session,
          ).updateMyTask(draft);
        }
        if (mounted) showDunesToast(context, '任务已更新');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: creating ? '新增失败' : '保存失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTask(WorkbenchKpiTask row) async {
    if (!_manageTasks || _busy) return;
    final ok = await _confirm(
      title: '确认删除任务？',
      content: '将删除「${row.name}」，删除后不可恢复。',
      confirmLabel: '确认删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.deleteTask != null) {
        await widget.deleteTask!(row.id);
      } else {
        await WorkbenchKpiService(session: widget.session).deleteMyTask(row.id);
      }
      if (mounted) showDunesToast(context, '已删除');
      await _load();
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '删除失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _score?.me;
    final canPrev = !_month.isAtSameMomentAs(_earliestMonth);
    final canNext = _month.isBefore(_currentMonth);
    final hasScore = person != null && person.categories.isNotEmpty;
    final empty = !hasScore && _tasks.isEmpty;
    return ColoredBox(
      key: ValueKey<int>(widget.session.userId),
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onBack: widget.onBack,
              onAdd: _manageTasks && !_busy
                  ? () => unawaited(_editTask(null))
                  : null,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _MonthBar(
                    label: formatKpiMonthLabel(_month),
                    canPrev: canPrev,
                    canNext: canNext,
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                    onPick: _pickMonth,
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _ErrorCard(onRetry: () => unawaited(_load()))
                  else if (empty)
                    const _EmptyCard()
                  else ...[
                    if (person != null) ...[
                      _SummaryCard(person: person),
                      const SizedBox(height: 14),
                    ],
                    if (_manageTasks && _tasks.isNotEmpty) ...[
                      Text(
                        '计入任务（${_tasks.length}）',
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF312249),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final task in _tasks)
                        _MineTaskCard(
                          task: task,
                          onEdit: _busy
                              ? null
                              : () => unawaited(_editTask(task)),
                          onDelete: _busy
                              ? null
                              : () => unawaited(_deleteTask(task)),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (hasScore)
                      for (final cat in person.categories) ...[
                        _CategoryBlock(category: cat),
                        const SizedBox(height: 14),
                      ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onAdd});

  final VoidCallback onBack;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFCFAFF),
        border: Border(bottom: BorderSide(color: Color(0xFFE7DFF0))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: const Color(0xFF4A3866),
          ),
          Expanded(
            child: Text(
              '绩效发展',
              style: DunesTypography.sans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF312249),
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              key: const Key('work-profile-perf-add'),
              tooltip: '新增任务',
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              color: const Color(0xFF4A3866),
            ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final String label;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('work-profile-perf-month-prev'),
            tooltip: '上个月',
            onPressed: canPrev ? onPrev : null,
            icon: const Icon(Icons.chevron_left_rounded),
            color: const Color(0xFF4A3866),
          ),
          Expanded(
            child: TextButton(
              key: const Key('work-profile-perf-month'),
              onPressed: onPick,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF312249),
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('work-profile-perf-month-next'),
            tooltip: '下个月',
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: const Color(0xFF4A3866),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Text(
              '加载失败，请稍后重试',
              key: const Key('work-profile-perf-error'),
              style: DunesTypography.sans(
                fontSize: 14,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(
                '重试',
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.coral,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.person});

  final WorkProfileKpiPerson person;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('work-profile-perf-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text(
                '主营 ${person.mainScore.toStringAsFixed(2)}',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF312249),
                ),
              ),
              _GradeChip(grade: person.resolvedGrade),
              if (person.bonus != 0)
                Text(
                  '加减分 ${formatKpiAdj(person.bonus)}',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB07A2B),
                  ),
                ),
              Text(
                '通信权重 ${person.telecomWeight.toStringAsFixed(4)}',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
              Text(
                '能源权重 ${person.energyWeight.toStringAsFixed(4)}',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          '本月暂无计入任务',
          key: const Key('work-profile-perf-empty'),
          style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
        ),
      ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({required this.category});

  final WorkProfileKpiCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6DCF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${category.categoryLabel}（${category.tasks.length}）',
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '板块得分 ${category.score.toStringAsFixed(2)} · 权重 ${category.categoryWeight.toStringAsFixed(4)}',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 8),
          for (final task in category.tasks) _TaskRow(task: task),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final WorkProfileKpiTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${task.taskName} · ${task.province.isEmpty ? '全国' : task.province}',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (task.weightOverridden)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '手工',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB07A2B),
                    ),
                  ),
                ),
              Text(
                '权重 ${task.weightPct.toStringAsFixed(2)}%',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.coral,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (task.weightOverridden && task.autoWeightPct != null)
            Text(
              '自动权重 ${task.autoWeightPct!.toStringAsFixed(2)}%',
              style: DunesTypography.sans(
                fontSize: 12,
                color: const Color(0xFFB07A2B),
              ),
            ),
          if (task.remark.isNotEmpty)
            Text(
              '备注 ${task.remark}',
              style: DunesTypography.sans(
                fontSize: 12,
                color: const Color(0xFFB07A2B),
              ),
            ),
          if (task.scoreAdjusted || task.scoreAdj != 0)
            Text(
              '加减分 ${formatKpiAdj(task.scoreAdj)}',
              style: DunesTypography.sans(
                fontSize: 12,
                color: const Color(0xFFB07A2B),
              ),
            ),
          Text(
            '上月收入 ${formatKpiNum(task.prevRevenue)} · 本月收入 ${formatKpiNum(task.curRevenue)}',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
          ),
          Text(
            '上月利润 ${formatKpiNum(task.prevProfit)} · 本月利润 ${formatKpiNum(task.curProfit)}',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
          ),
          Text(
            '上月用户 ${formatKpiNum(task.prevUsers)} · 本月用户 ${formatKpiNum(task.curUsers)}',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
          ),
          Text(
            task.scoreAdjusted && task.autoTaskTotal != null
                ? '得分 ${task.taskTotal.toStringAsFixed(1)}（自动 ${task.autoTaskTotal!.toStringAsFixed(1)}） · ${task.metrics.map((m) => m.line).join('；')}'
                : '得分 ${task.taskTotal.toStringAsFixed(1)} · ${task.metrics.map((m) => m.line).join('；')}',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final KpiGrade grade;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('work-profile-perf-grade'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${grade.label} · 系数 ${formatKpiCoefficient(grade.coefficient)}',
        style: DunesTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _perfAccent,
        ),
      ),
    );
  }
}

class _MineTaskCard extends StatelessWidget {
  const _MineTaskCard({required this.task, this.onEdit, this.onDelete});

  final WorkbenchKpiTask task;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final range =
        '${task.startDate.isEmpty ? '不限' : task.startDate} ~ ${task.endDate.isEmpty ? '不限' : task.endDate}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6DCF0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      task.province.isEmpty ? '全国' : task.province,
                      if (task.tagName.isNotEmpty) task.tagName,
                      range,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: task.isCounted
                    ? const Color(0xFFEAEFDF)
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                task.isCounted ? '计入' : '不计',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: task.isCounted
                      ? const Color(0xFF5D8A4E)
                      : DunesColors.text3,
                ),
              ),
            ),
            IconButton(
              key: Key('work-profile-perf-edit-${task.id}'),
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
            IconButton(
              key: Key('work-profile-perf-delete-${task.id}'),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerfTaskEditorDialog extends StatefulWidget {
  const _PerfTaskEditorDialog({required this.initial});

  final WorkbenchKpiTask initial;

  @override
  State<_PerfTaskEditorDialog> createState() => _PerfTaskEditorDialogState();
}

class _PerfTaskEditorDialogState extends State<_PerfTaskEditorDialog> {
  late WorkbenchKpiTask _draft;
  final _nameCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _nameCtrl.text = _draft.name;
    _provinceCtrl.text = _draft.province;
    _contentCtrl.text = _draft.content;
    _tagCtrl.text = _draft.tagName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _provinceCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final raw = start ? _draft.startDate : _draft.endDate;
    final parsed = DateTime.tryParse(raw);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final text =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      _draft = start
          ? _draft.copyWith(startDate: text)
          : _draft.copyWith(endDate: text);
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showDunesToast(context, '请填写任务名称', kind: DunesToastKind.error);
      return;
    }
    Navigator.pop(
      context,
      _draft.copyWith(
        name: name,
        province: _provinceCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        tagName: _tagCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creating = _draft.id <= 0;
    final maxW = (MediaQuery.sizeOf(context).width - 40).clamp(280.0, 420.0);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(creating ? '新增任务' : '编辑任务'),
      content: SizedBox(
        width: maxW,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '任务名称',
                  hintText: '如：中石油、小套-加油会员',
                ),
              ),
              TextField(
                controller: _provinceCtrl,
                decoration: const InputDecoration(
                  labelText: '省份',
                  hintText: '空或全国=全国合计；可填广东,广西',
                ),
              ),
              TextField(
                controller: _contentCtrl,
                decoration: const InputDecoration(labelText: '内容'),
              ),
              TextField(
                controller: _tagCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '标签I / 标签II',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始日期'),
                subtitle: Text(
                  _draft.startDate.isEmpty ? '不限' : _draft.startDate,
                ),
                onTap: () => unawaited(_pickDate(start: true)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('结束日期'),
                subtitle: Text(_draft.endDate.isEmpty ? '不限' : _draft.endDate),
                onTap: () => unawaited(_pickDate(start: false)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('计入绩效'),
                value: _draft.isCounted,
                onChanged: (v) => setState(() {
                  _draft = _draft.copyWith(isCounted: v);
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('work-profile-perf-editor-save'),
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: _perfAccent),
          child: const Text('下一步'),
        ),
      ],
    );
  }
}
