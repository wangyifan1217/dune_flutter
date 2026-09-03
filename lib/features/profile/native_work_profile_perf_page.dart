import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'work_profile_kpi.dart';

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

DateTime kpiShiftMonth(DateTime d, int delta) => DateTime(d.year, d.month + delta);

DateTime parseKpiMonth(String raw, DateTime fallback) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return kpiMonthStart(fallback);
  return DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
}

/// 绩效发展只读列表：通信 / 能源分开，任务权重按当月收入占比自动分摊。
/// 默认当月，可自选月份；未注入 [score] 时请求 `/kpi/my-score`。
class NativeWorkProfilePerfPage extends StatefulWidget {
  const NativeWorkProfilePerfPage({
    super.key,
    required this.session,
    required this.onBack,
    this.score,
    this.now,
    this.loadScore,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final WorkProfileKpiScore? score;
  final DateTime? now;
  final Future<WorkProfileKpiScore> Function(String month)? loadScore;

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

  DateTime get _clock => widget.now ?? DateTime.now();
  DateTime get _currentMonth => kpiMonthStart(_clock);
  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

  @override
  void initState() {
    super.initState();
    final injected = widget.score?.month ?? '';
    _month = injected.isEmpty
        ? _currentMonth
        : parseKpiMonth(injected, _currentMonth);
    _score = widget.score;
    if (widget.score != null) {
      _loading = false;
    } else {
      unawaited(_load());
    }
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
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _score = score;
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

  @override
  Widget build(BuildContext context) {
    final person = _score?.me;
    final canPrev = !_month.isAtSameMomentAs(_earliestMonth);
    final canNext = _month.isBefore(_currentMonth);
    return ColoredBox(
      key: ValueKey<int>(widget.session.userId),
      color: const Color(0xFFF8F5FC),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: widget.onBack),
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
                  else if (person == null || person.categories.isEmpty)
                    const _EmptyCard()
                  else ...[
                    _SummaryCard(person: person),
                    const SizedBox(height: 14),
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
  const _Header({required this.onBack});

  final VoidCallback onBack;

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
          Text(
            '绩效发展',
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF312249),
            ),
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
              style: DunesTypography.sans(fontSize: 14, color: DunesColors.text3),
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
                style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
              ),
              Text(
                '能源权重 ${person.energyWeight.toStringAsFixed(4)}',
                style: DunesTypography.sans(fontSize: 12, color: DunesColors.text2),
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
