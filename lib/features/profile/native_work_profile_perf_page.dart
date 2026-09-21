import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_month_picker.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../kpi/kpi_metric_list.dart';
import '../shell/dunes_toast.dart';
import 'work_profile_controls.dart';
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

String formatKpiMonth(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

String formatKpiMonthLabel(DateTime d) => '${d.year}年${d.month}月';

DateTime kpiMonthStart(DateTime d) => DateTime(d.year, d.month);

DateTime kpiDefaultScoreMonth(DateTime now) =>
    DateTime(now.year, now.month - 1);

DateTime kpiShiftMonth(DateTime d, int delta) =>
    DateTime(d.year, d.month + delta);

DateTime parseKpiMonth(String raw, DateTime fallback) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return kpiMonthStart(fallback);
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// 绩效发展：按灯塔数据规则查看切片与得分等级，不可自行增改。
/// 默认上一自然月（与工作台月度绩效考评、灯塔月报一致），可自选月份；
/// 未注入 [score] 时请求 `/kpi/my-score`。
class NativeWorkProfilePerfPage extends StatefulWidget {
  const NativeWorkProfilePerfPage({
    super.key,
    required this.session,
    required this.onBack,
    this.score,
    this.initialMonth,
    this.now,
    this.loadScore,
    this.ackScore,
    this.submitAppeal,
    this.listMyAppeals,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final WorkProfileKpiScore? score;
  final DateTime? initialMonth;
  final DateTime? now;
  final Future<WorkProfileKpiScore> Function(String month)? loadScore;
  final Future<WorkProfileKpiScore> Function(String month)? ackScore;
  final Future<KpiAppeal> Function(String month, String comment)? submitAppeal;
  final Future<List<KpiAppeal>> Function(String month)? listMyAppeals;

  @override
  State<NativeWorkProfilePerfPage> createState() =>
      _NativeWorkProfilePerfPageState();
}

class _NativeWorkProfilePerfPageState extends State<NativeWorkProfilePerfPage> {
  late DateTime _month;
  WorkProfileKpiScore? _score;
  bool _loading = true;
  Object? _error;
  int _loadGen = 0;
  List<KpiAppeal> _appeals = const [];

  DateTime get _clock => widget.now ?? DateTime.now();
  DateTime get _currentMonth => kpiMonthStart(_clock);
  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

  @override
  void initState() {
    super.initState();
    final injected = widget.score?.month ?? '';
    _month = injected.isNotEmpty
        ? parseKpiMonth(injected, _currentMonth)
        : kpiMonthStart(widget.initialMonth ?? kpiDefaultScoreMonth(_clock));
    _score = widget.score;
    if (widget.score != null) {
      _loading = false;
    } else {
      unawaited(_load());
    }
    unawaited(_refreshAppeals());
  }

  Future<void> _load() async {
    if (widget.score != null) {
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
      final score = widget.loadScore != null
          ? await widget.loadScore!(month)
          : await WorkProfileKpiService(
              session: widget.session,
            ).fetchMyScore(month: month);
      final appeals = await _fetchAppeals(month);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _score = score;
        _appeals = appeals;
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

  Future<List<KpiAppeal>> _fetchAppeals(String month) async {
    try {
      if (widget.listMyAppeals != null) {
        return await widget.listMyAppeals!(month);
      }
      if (widget.score != null) return const [];
      return await WorkProfileKpiService(
        session: widget.session,
      ).listMyAppeals(month: month);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _refreshAppeals() async {
    final appeals = await _fetchAppeals(formatKpiMonth(_month));
    if (!mounted) return;
    setState(() => _appeals = appeals);
  }

  Future<void> _pickMonth() async {
    final picked = await showDunesMonthPicker(
      context: context,
      initialMonth: _month,
      firstMonth: _earliestMonth,
      lastMonth: _currentMonth,
      title: '选择月份',
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

  Future<void> _ack() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认本月绩效？'),
        content: const Text('确认后表示已知悉并接受本月量表结果。改分后需重新确认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('work-profile-perf-ack-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final month = formatKpiMonth(_month);
      final score = widget.ackScore != null
          ? await widget.ackScore!(month)
          : await WorkProfileKpiService(
              session: widget.session,
            ).ackRubricScore(month: month);
      if (!mounted) return;
      setState(() => _score = score);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _openAppeal() async {
    final person = _score?.me;
    if (person == null) return;
    final isRubric = person.isRubric;
    final tasks = [for (final category in person.categories) ...category.tasks];
    final draft = await showDialog<_KpiAppealDraft>(
      context: context,
      builder: (ctx) => _KpiAppealDialog(isRubric: isRubric, tasks: tasks),
    );
    if (draft == null || !mounted) return;
    try {
      final month = formatKpiMonth(_month);
      final saved = widget.submitAppeal != null
          ? await widget.submitAppeal!(month, draft.comment)
          : await WorkProfileKpiService(session: widget.session).submitAppeal(
              month: month,
              comment: draft.comment,
              subjectTaskId: draft.taskId,
              expectedChange: draft.expectedChange,
            );
      if (!mounted) return;
      setState(() => _appeals = [saved, ..._appeals]);
      showDunesToast(context, '已提交');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '申诉失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _score?.me;
    final canPrev = !_month.isAtSameMomentAs(_earliestMonth);
    final canNext = _month.isBefore(_currentMonth);
    final hasScore = person != null && person.categories.isNotEmpty;
    final empty = !hasScore;
    return ColoredBox(
      key: ValueKey<int>(widget.session.userId),
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onBack: widget.onBack,
              onAppeal: hasScore ? () => unawaited(_openAppeal()) : null,
              appealed: _appeals.any((a) => a.isOpen),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  WorkProfileMonthBar(
                    label: formatKpiMonthLabel(_month),
                    canPrev: canPrev,
                    canNext: canNext,
                    onPrev: () => _shiftMonth(-1),
                    onNext: () => _shiftMonth(1),
                    onPick: _pickMonth,
                    monthKey: const Key('work-profile-perf-month'),
                    prevKey: const Key('work-profile-perf-month-prev'),
                    nextKey: const Key('work-profile-perf-month-next'),
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
                    _SummaryCard(person: person),
                    if (person.isRubric && person.isAcked) ...[
                      const SizedBox(height: 8),
                      Text(
                        '已确认 ${formatKpiAckedAt(person.ackedAt)}',
                        key: const Key('work-profile-perf-acked'),
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.text2,
                        ),
                      ),
                    ],
                    if (person.canAck) ...[
                      const SizedBox(height: 10),
                      FilledButton(
                        key: const Key('work-profile-perf-ack'),
                        onPressed: _loading ? null : () => unawaited(_ack()),
                        style: FilledButton.styleFrom(
                          backgroundColor: _perfAccent,
                        ),
                        child: const Text('确认本月绩效'),
                      ),
                    ],
                    const SizedBox(height: 14),
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
  const _Header({required this.onBack, this.onAppeal, this.appealed = false});

  final VoidCallback onBack;
  final VoidCallback? onAppeal;
  final bool appealed;

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
          if (onAppeal != null)
            TextButton(
              key: const Key('work-profile-perf-appeal'),
              onPressed: onAppeal,
              child: Text(
                appealed ? '已申诉' : '绩效申诉',
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _perfAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KpiAppealDraft {
  const _KpiAppealDraft({
    required this.taskId,
    required this.comment,
    required this.expectedChange,
  });

  final int taskId;
  final String comment;
  final String expectedChange;
}

class _KpiAppealDialog extends StatefulWidget {
  const _KpiAppealDialog({required this.isRubric, required this.tasks});

  final bool isRubric;
  final List<WorkProfileKpiTask> tasks;

  @override
  State<_KpiAppealDialog> createState() => _KpiAppealDialogState();
}

class _KpiAppealDialogState extends State<_KpiAppealDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _expectedController;
  int _taskId = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _expectedController = TextEditingController();
    if (widget.tasks.isNotEmpty) _taskId = widget.tasks.first.taskId;
  }

  @override
  void dispose() {
    _controller.dispose();
    _expectedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(kpiAppealTitle(isRubric: widget.isRubric)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              key: const Key('work-profile-perf-appeal-subject'),
              initialValue: _taskId == 0 ? null : _taskId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '申诉指标'),
              items: [
                for (final task in widget.tasks)
                  DropdownMenuItem(
                    value: task.taskId,
                    child: Text(
                      [
                        task.taskName,
                        if (task.province.trim().isNotEmpty) task.province,
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _taskId = value ?? 0),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('work-profile-perf-appeal-expected'),
              controller: _expectedController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '期望修正为',
                hintText: '例如：湖南满减券应计入本月营收和利润',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('work-profile-perf-appeal-comment'),
              controller: _controller,
              maxLines: 4,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '申诉理由',
                hintText: '写清数据来源和判断依据',
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
        FilledButton(
          key: const Key('work-profile-perf-appeal-ok'),
          onPressed: _taskId == 0
              ? null
              : () => Navigator.pop(
                  context,
                  _KpiAppealDraft(
                    taskId: _taskId,
                    comment: _controller.text.trim(),
                    expectedChange: _expectedController.text.trim(),
                  ),
                ),
          child: const Text('提交'),
        ),
      ],
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
                person.isRubric
                    ? '量表 ${person.mainScore.toStringAsFixed(2)}'
                    : '主营 ${person.mainScore.toStringAsFixed(2)}',
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
              if (!person.isRubric) ...[
                Text(
                  '运营商权重 ${person.telecomWeight.toStringAsFixed(4)}',
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
          '本月暂无对应的灯塔数据规则',
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
            category.category == 'rd' || category.category == 'office'
                ? '${category.categoryLabel}（${category.tasks.length}项）'
                : '${category.categoryLabel}（${category.tasks.length}条规则）',
            style: DunesTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            category.category == 'rd' || category.category == 'office'
                ? '量表得分 ${category.score.toStringAsFixed(2)}'
                : '板块得分 ${category.score.toStringAsFixed(2)} · 权重 ${category.categoryWeight.toStringAsFixed(4)}',
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
    final bucket = task.bucketLabel.replaceAll('板块', '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F5FC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6DCF0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kpiLighthouseSliceTitle(task),
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        kpiLighthouseSliceSubtitle(task),
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (bucket.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        bucket,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                  ),
                Text(
                  task.isRubric
                      ? '${task.taskTotal.toStringAsFixed(1)} / ${task.weightPct == task.weightPct.roundToDouble() ? task.weightPct.toStringAsFixed(0) : task.weightPct.toStringAsFixed(1)}'
                      : task.taskTotal.toStringAsFixed(1),
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: DunesColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!task.isRubric)
              Row(
                children: [
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
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.coral,
                    ),
                  ),
                ],
              ),
            if (!task.isRubric &&
                task.weightOverridden &&
                task.autoWeightPct != null)
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
            if (!task.isRubric) ...[
              Text(
                '本月营收 ${kpiMoney(task.curRevenue)} · 上月 ${kpiMoney(task.prevRevenue)}',
                style: DunesTypography.sans(
                  fontSize: 12,
                  color: DunesColors.text2,
                ),
              ),
              Text(
                task.scoreAdjusted && task.autoTaskTotal != null
                    ? '任务分 ${task.taskTotal.toStringAsFixed(1)}（自动 ${task.autoTaskTotal!.toStringAsFixed(1)}）'
                    : '任务分 ${task.taskTotal.toStringAsFixed(1)}',
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text2,
                ),
              ),
            ],
            const SizedBox(height: 6),
            // 收入/利润/用户的本月上月都在指标明细里，不再单独铺三行文字。
            KpiMetricList(metrics: task.metrics),
          ],
        ),
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
