import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import 'kpi_metric_list.dart';
import 'workbench_kpi_service.dart';

const _accent = DunesColors.brandPurple;

double kpiPreviewCategoryScore({
  required WorkProfileKpiCategory category,
  required Map<int, TextEditingController> weightCtrls,
  required Map<int, TextEditingController> adjCtrls,
}) {
  var score = 0.0;
  for (final task in category.tasks) {
    final weight =
        kpiParseAdjustNum(weightCtrls[task.taskId]?.text ?? '') ??
        task.weightPct;
    final adj =
        kpiParseAdjustNum(adjCtrls[task.taskId]?.text ?? '') ?? task.scoreAdj;
    score += kpiWeightedContribution(
      kpiPreviewTaskTotal(
        taskTotal: task.taskTotal,
        scoreAdj: task.scoreAdj,
        autoTaskTotal: task.autoTaskTotal,
        adj: adj,
      ),
      weight,
    );
  }
  return score;
}

double kpiPreviewMainScore({
  required WorkProfileKpiPerson person,
  required Map<int, TextEditingController> weightCtrls,
  required Map<int, TextEditingController> adjCtrls,
  double? telecomWeight,
  double? energyWeight,
}) {
  var telecom = 0.0;
  var energy = 0.0;
  for (final cat in person.categories) {
    final score = kpiPreviewCategoryScore(
      category: cat,
      weightCtrls: weightCtrls,
      adjCtrls: adjCtrls,
    );
    if (cat.category == 'energy') {
      energy = score;
    } else {
      telecom = score;
    }
  }
  return telecom * (telecomWeight ?? person.telecomWeight) +
      energy * (energyWeight ?? person.energyWeight);
}

/// 百分数显示：整数不带小数，其余最多两位。
String kpiFormatSharePct(double v) {
  final r = (v * 100).roundToDouble() / 100;
  if (r == r.roundToDouble()) return r.toInt().toString();
  var s = r.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

/// '2026-09' → '2026年9月'
String kpiFormatYm(String ym) {
  final parts = ym.trim().split('-');
  if (parts.length < 2) return ym;
  final m = int.tryParse(parts[1]);
  return m == null ? ym : '${parts[0]}年$m月';
}

class WorkbenchKpiDetailPane extends StatefulWidget {
  const WorkbenchKpiDetailPane({
    super.key,
    required this.personName,
    required this.monthLabel,
    required this.score,
    required this.canEdit,
    this.busy = false,
    this.onSave,
    this.onSaveRubric,
    this.onSkip,
    this.onAck,
  });

  final String personName;
  final String monthLabel;
  final WorkProfileKpiScore score;
  final bool canEdit;
  final bool busy;
  final Future<void> Function(
    List<WorkbenchKpiOverrideItem> items,
    WorkbenchKpiCategoryWeight? categoryWeight,
    String summary,
  )?
  onSave;
  final Future<void> Function(
    List<WorkbenchKpiRubricItem> items,
    String summary,
  )?
  onSaveRubric;
  final Future<void> Function(String reason)? onSkip;
  final Future<void> Function()? onAck;

  @override
  State<WorkbenchKpiDetailPane> createState() => _WorkbenchKpiDetailPaneState();
}

class _WorkbenchKpiDetailPaneState extends State<WorkbenchKpiDetailPane> {
  final Map<int, TextEditingController> _weightCtrls = {};
  final Map<int, TextEditingController> _adjCtrls = {};
  final Map<int, TextEditingController> _remarkCtrls = {};
  final Map<int, TextEditingController> _pointCtrls = {};
  final TextEditingController _telecomShareCtrl = TextEditingController();
  final TextEditingController _energyShareCtrl = TextEditingController();

  /// 板块占比是否按营收自动；手改输入框后变 false，点「恢复按营收自动」变回 true。
  bool _shareAuto = true;
  String? _shareError;
  String? _rubricError;
  bool _syncingCtrls = false;

  WorkProfileKpiPerson? get _person =>
      widget.score.people.isEmpty ? null : widget.score.people.first;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant WorkbenchKpiDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    for (final c in _weightCtrls.values) {
      c.removeListener(_onPreviewTick);
      c.dispose();
    }
    for (final c in _adjCtrls.values) {
      c.removeListener(_onPreviewTick);
      c.dispose();
    }
    for (final c in _remarkCtrls.values) {
      c.removeListener(_onPreviewTick);
      c.dispose();
    }
    for (final c in _pointCtrls.values) {
      c.dispose();
    }
    _telecomShareCtrl.dispose();
    _energyShareCtrl.dispose();
    super.dispose();
  }

  void _onPreviewTick() {
    if (_syncingCtrls || !mounted) return;
    setState(() {});
  }

  TextEditingController _ctrl(
    Map<int, TextEditingController> map,
    int id,
  ) {
    return map.putIfAbsent(id, () {
      final ctrl = TextEditingController();
      ctrl.addListener(_onPreviewTick);
      return ctrl;
    });
  }

  void _syncControllers() {
    _syncingCtrls = true;
    final seen = <int>{};
    for (final task in _allTasks()) {
      seen.add(task.taskId);
      _ctrl(_weightCtrls, task.taskId).text = task.weightPct.toStringAsFixed(2);
      _ctrl(_adjCtrls, task.taskId).text =
          task.scoreAdj == 0 ? '0' : formatKpiAdj(task.scoreAdj);
      _ctrl(_remarkCtrls, task.taskId).text = task.remark;
      final scoreMetric = task.metrics.isEmpty ? null : task.metrics.first;
      final pts =
          scoreMetric?.points ?? (task.isRubric ? null : task.taskTotal);
      _pointCtrls
          .putIfAbsent(task.taskId, () => TextEditingController())
          .text = pts == null
          ? ''
          : (pts == pts.roundToDouble()
                ? pts.toInt().toString()
                : pts.toString());
    }
    _weightCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.removeListener(_onPreviewTick);
      ctrl.dispose();
      return true;
    });
    _adjCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.removeListener(_onPreviewTick);
      ctrl.dispose();
      return true;
    });
    _remarkCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.removeListener(_onPreviewTick);
      ctrl.dispose();
      return true;
    });
    _pointCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.dispose();
      return true;
    });
    final person = _person;
    if (person != null) {
      _shareAuto = !person.categoryWeightManual;
      _shareError = null;
      _telecomShareCtrl.text = kpiFormatSharePct(person.telecomWeight * 100);
      _energyShareCtrl.text = kpiFormatSharePct(person.energyWeight * 100);
    }
    _syncingCtrls = false;
  }

  void _onTelecomShareChanged(String raw) {
    final v = double.tryParse(raw.trim());
    setState(() {
      _shareAuto = false;
      _shareError = null;
      if (v != null && v >= 0 && v <= 100) {
        _energyShareCtrl.text = kpiFormatSharePct(100 - v);
      }
    });
  }

  void _onEnergyShareChanged(String raw) {
    final v = double.tryParse(raw.trim());
    setState(() {
      _shareAuto = false;
      _shareError = null;
      if (v != null && v >= 0 && v <= 100) {
        _telecomShareCtrl.text = kpiFormatSharePct(100 - v);
      }
    });
  }

  void _resetShareAuto() {
    final person = _person;
    if (person == null) return;
    setState(() {
      _shareAuto = true;
      _shareError = null;
      _telecomShareCtrl.text = kpiFormatSharePct(
        person.autoTelecomWeight * 100,
      );
      _energyShareCtrl.text = kpiFormatSharePct(person.autoEnergyWeight * 100);
    });
  }

  /// 预览用的板块占比（0~1）。输入框没填完整时沿用服务端的值。
  (double, double) _previewSectorWeights(WorkProfileKpiPerson person) {
    if (!person.hasBothSectors) {
      return (person.telecomWeight, person.energyWeight);
    }
    if (_shareAuto) return (person.autoTelecomWeight, person.autoEnergyWeight);
    final t = double.tryParse(_telecomShareCtrl.text.trim());
    final e = double.tryParse(_energyShareCtrl.text.trim());
    if (t == null || e == null) {
      return (person.telecomWeight, person.energyWeight);
    }
    return (t / 100, e / 100);
  }

  /// 板块占比有变化才返回；校验不过时写 [_shareError] 并返回 null。
  WorkbenchKpiCategoryWeight? _collectCategoryWeight() {
    _shareError = null;
    final person = _person;
    if (person == null || !person.hasBothSectors) return null;
    if (_shareAuto) {
      return person.categoryWeightManual
          ? const WorkbenchKpiCategoryWeight.auto()
          : null;
    }
    final t = double.tryParse(_telecomShareCtrl.text.trim());
    final e = double.tryParse(_energyShareCtrl.text.trim());
    if (t == null || e == null) {
      _shareError = '请填写运营商和能源的板块占比';
      return null;
    }
    if (t < 0 || t > 100 || e < 0 || e > 100) {
      _shareError = '板块占比需在 0 到 100 之间';
      return null;
    }
    if ((t + e - 100).abs() > 0.01) {
      _shareError =
          '运营商 + 能源合计需为 100%，当前 ${kpiFormatSharePct(t + e)}%';
      return null;
    }
    final same =
        (t - person.telecomWeight * 100).abs() < 0.005 &&
        (e - person.energyWeight * 100).abs() < 0.005;
    if (person.categoryWeightManual && same) return null;
    // 自动状态下手填（哪怕填的就是当月营收比例）也按手工保存，之后各月固定这个比例。
    return WorkbenchKpiCategoryWeight.manual(telecomPct: t, energyPct: e);
  }

  String _categoryWeightSummary(WorkbenchKpiCategoryWeight cw) {
    final person = _person!;
    final before =
        '运营商 ${kpiFormatSharePct(person.telecomWeight * 100)}% / 能源 ${kpiFormatSharePct(person.energyWeight * 100)}%';
    if (cw.auto) {
      return '板块占比 $before → 按营收自动（运营商 ${kpiFormatSharePct(person.autoTelecomWeight * 100)}% / 能源 ${kpiFormatSharePct(person.autoEnergyWeight * 100)}%），${widget.monthLabel}起';
    }
    return '板块占比 $before → 运营商 ${kpiFormatSharePct(cw.telecomPct!)}% / 能源 ${kpiFormatSharePct(cw.energyPct!)}%，${widget.monthLabel}起之后各月沿用';
  }

  List<WorkProfileKpiTask> _allTasks() {
    final person = _person;
    if (person == null) return const [];
    return [for (final cat in person.categories) ...cat.tasks];
  }

  List<WorkbenchKpiOverrideItem> _collectItems() {
    final items = <WorkbenchKpiOverrideItem>[];
    for (final task in _allTasks()) {
      final rawWeight = _weightCtrls[task.taskId]?.text.trim() ?? '';
      final rawAdj = _adjCtrls[task.taskId]?.text.trim() ?? '';
      final remark = _remarkCtrls[task.taskId]?.text.trim() ?? '';
      final parsed = double.tryParse(rawWeight);
      final parsedAdj = rawAdj.isEmpty || rawAdj == '+' || rawAdj == '-'
          ? 0.0
          : double.tryParse(rawAdj);
      final auto = task.autoWeightPct ?? task.weightPct;
      final weightChanged = parsed != null && (parsed - auto).abs() > 0.05;
      final adjChanged =
          parsedAdj != null && (parsedAdj - task.scoreAdj).abs() > 0.05;
      final keepAdj = parsedAdj != null && parsedAdj.abs() > 0.05;
      if (!weightChanged && !adjChanged && !keepAdj && remark.isEmpty) continue;
      items.add(
        WorkbenchKpiOverrideItem(
          taskId: task.taskId,
          weightPct: weightChanged ? parsed : null,
          scoreAdj: keepAdj || adjChanged ? parsedAdj : null,
          remark: remark,
        ),
      );
    }
    return items;
  }

  List<String> _taskSummaryLines(List<WorkbenchKpiOverrideItem> items) {
    final byId = {for (final t in _allTasks()) t.taskId: t};
    final lines = <String>[];
    for (final item in items) {
      final task = byId[item.taskId];
      if (task == null) continue;
      final auto = task.autoWeightPct ?? task.weightPct;
      final next = item.weightPct ?? task.weightPct;
      final parts = <String>[
        '${auto.toStringAsFixed(2)}% → ${next.toStringAsFixed(2)}%',
      ];
      if (item.scoreAdj != null && item.scoreAdj!.abs() > 0.005) {
        parts.add('加减分 ${formatKpiAdj(item.scoreAdj!)}');
      } else if (task.scoreAdj.abs() > 0.005) {
        parts.add('加减分清零');
      }
      if (item.remark.isNotEmpty) {
        parts.add('备注：${item.remark}');
      }
      lines.add('${task.taskName}  ${parts.join('，')}');
    }
    return lines;
  }

  Future<void> _submit() async {
    final onSave = widget.onSave;
    if (onSave == null || widget.busy) return;
    final items = _collectItems();
    final categoryWeight = _collectCategoryWeight();
    if (_shareError != null) {
      setState(() {});
      return;
    }
    final head = '${widget.personName} ${widget.monthLabel}';
    final String summary;
    if (items.isEmpty && categoryWeight == null) {
      summary = '$head\n将清空手工权重、加减分和备注，恢复自动计算。';
    } else {
      final hadTaskAdjust = _allTasks().any(
        (t) => t.weightOverridden || t.scoreAdjusted || t.remark.isNotEmpty,
      );
      summary = [
        head,
        if (categoryWeight != null) _categoryWeightSummary(categoryWeight),
        ..._taskSummaryLines(items),
        if (items.isEmpty && hadTaskAdjust) '清空任务手工权重、加减分和备注',
      ].join('\n');
    }
    await onSave(items, categoryWeight, summary);
  }

  Future<void> _submitRubric() async {
    final onSave = widget.onSaveRubric;
    if (onSave == null || widget.busy) return;
    final items = <WorkbenchKpiRubricItem>[];
    for (final task in _allTasks()) {
      final key = task.rubricKey;
      if (key.isEmpty) continue;
      final raw = _pointCtrls[task.taskId]?.text.trim() ?? '';
      final remark = _remarkCtrls[task.taskId]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final parsed = double.tryParse(raw);
      if (parsed == null) {
        setState(() => _rubricError = '${task.taskName} 请填数字');
        return;
      }
      items.add(
        WorkbenchKpiRubricItem(key: key, points: parsed, remark: remark),
      );
    }
    setState(() => _rubricError = null);
    final byKey = {for (final t in _allTasks()) t.rubricKey: t};
    final summary = items.isEmpty
        ? '${widget.personName} ${widget.monthLabel}\n将清空已录量表分，变回未评分。'
        : '${widget.personName} ${widget.monthLabel}\n${[for (final e in items) '${byKey[e.key]?.taskName ?? e.key}  ${e.points}${e.remark.isEmpty ? '' : '  ${e.remark}'}'].join('\n')}';
    await onSave(items, summary);
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    if (person == null || person.categories.isEmpty) {
      return Center(
        child: Text(
          '该月暂无计入绩效明细',
          style: TextStyle(
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      );
    }
    final sectorWeights = _previewSectorWeights(person);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.personName} · ${widget.monthLabel}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
          if (person.isRubric && person.scoredByName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '考核人 ${person.scoredByName}',
              key: const Key('kpi-scored-by'),
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ],
          if (person.isRubric && person.isAcked) ...[
            const SizedBox(height: 4),
            Text(
              '被考核人已确认 ${formatKpiAckedAt(person.ackedAt)}',
              key: const Key('kpi-acked'),
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ] else if (person.isRubric && person.isUnpublished) ...[
            const SizedBox(height: 4),
            Text(
              '尚未发布到绩效助手',
              key: Key('kpi-unpublished'),
              style: TextStyle(
                fontSize: 13,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _ScoreHeader(
            person: person,
            telecomWeight: sectorWeights.$1,
            energyWeight: sectorWeights.$2,
            manualShare: person.hasBothSectors && !_shareAuto,
            previewMainScore: person.isRubric
                ? null
                : kpiPreviewMainScore(
                    person: person,
                    weightCtrls: _weightCtrls,
                    adjCtrls: _adjCtrls,
                    telecomWeight: sectorWeights.$1,
                    energyWeight: sectorWeights.$2,
                  ),
          ),
          if (widget.canEdit && widget.onSkip != null) ...[
            const SizedBox(height: 10),
            _KpiSkipBar(
              person: person,
              busy: widget.busy,
              onSkip: widget.onSkip!,
            ),
          ],
          const SizedBox(height: 12),
          if (person.isRubric) ...[
            for (final cat in person.categories) ...[
              _RubricCategoryEditor(
                category: cat,
                canEdit: widget.canEdit,
                pointCtrls: _pointCtrls,
                remarkCtrls: _remarkCtrls,
                onChanged: () => setState(() => _rubricError = null),
              ),
              const SizedBox(height: 12),
            ],
            if (_rubricError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _rubricError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: DunesColors.resolveNullable(
                      context,
                      Color(0xFFB42318),
                    ),
                  ),
                ),
              ),
            if (widget.canEdit)
              FilledButton(
                key: const Key('kpi-detail-save'),
                onPressed: widget.busy
                    ? null
                    : () => unawaited(_submitRubric()),
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: Text(widget.busy ? '保存中…' : '保存量表分'),
              ),
            if (widget.onAck != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const Key('kpi-ack'),
                onPressed: widget.busy
                    ? null
                    : () => unawaited(widget.onAck!()),
                child: const Text('确认本月绩效'),
              ),
            ],
          ] else ...[
            if (person.hasBothSectors) ...[
              _SectorShareEditor(
                person: person,
                scoreMonth: widget.score.month,
                monthLabel: widget.monthLabel,
                canEdit: widget.canEdit,
                auto: _shareAuto,
                error: _shareError,
                telecomCtrl: _telecomShareCtrl,
                energyCtrl: _energyShareCtrl,
                telecomWeight: sectorWeights.$1,
                energyWeight: sectorWeights.$2,
                weightCtrls: _weightCtrls,
                onTelecomChanged: _onTelecomShareChanged,
                onEnergyChanged: _onEnergyShareChanged,
                onResetAuto: _resetShareAuto,
              ),
              const SizedBox(height: 12),
            ],
            for (final cat in person.categories) ...[
              _CategoryEditor(
                category: cat,
                canEdit: widget.canEdit,
                weightCtrls: _weightCtrls,
                adjCtrls: _adjCtrls,
                remarkCtrls: _remarkCtrls,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.canEdit)
              FilledButton(
                key: const Key('kpi-detail-save'),
                onPressed: widget.busy ? null : () => unawaited(_submit()),
                style: FilledButton.styleFrom(backgroundColor: _accent),
                child: Text(widget.busy ? '保存中…' : '保存变更'),
              ),
          ],
        ],
      ),
    );
  }
}

/// 同时负责运营商、能源两个板块的人：调板块间占比，并列出每条任务的最终占比
///（板块占比 × 板块内权重），合计 100%。
class _SectorShareEditor extends StatelessWidget {
  const _SectorShareEditor({
    required this.person,
    required this.scoreMonth,
    required this.monthLabel,
    required this.canEdit,
    required this.auto,
    required this.error,
    required this.telecomCtrl,
    required this.energyCtrl,
    required this.telecomWeight,
    required this.energyWeight,
    required this.weightCtrls,
    required this.onTelecomChanged,
    required this.onEnergyChanged,
    required this.onResetAuto,
  });

  final WorkProfileKpiPerson person;
  final String scoreMonth;
  final String monthLabel;
  final bool canEdit;
  final bool auto;
  final String? error;
  final TextEditingController telecomCtrl;
  final TextEditingController energyCtrl;
  final double telecomWeight;
  final double energyWeight;
  final Map<int, TextEditingController> weightCtrls;
  final ValueChanged<String> onTelecomChanged;
  final ValueChanged<String> onEnergyChanged;
  final VoidCallback onResetAuto;

  String get _hint {
    if (auto) {
      return person.categoryWeightManual
          ? '保存后从$monthLabel起恢复按营收自动分摊'
          : '默认按两边当月营收分摊；手改后从$monthLabel起生效，之后各月沿用，直到再次修改';
    }
    final from = person.categoryWeightFrom.trim();
    if (person.categoryWeightManual && from.isNotEmpty && from != scoreMonth) {
      return '沿用${kpiFormatYm(from)}起的手工设定；在这里改会从$monthLabel起生效';
    }
    return '手工设定，$monthLabel起生效，之后各月沿用，直到再次修改';
  }

  double _taskWeight(WorkProfileKpiTask task) =>
      kpiParseAdjustNum(weightCtrls[task.taskId]?.text ?? '') ?? task.weightPct;

  @override
  Widget build(BuildContext context) {
    final text2 = DunesColors.resolve(context, DunesColors.text2);
    final text3 = DunesColors.resolve(context, DunesColors.text3);
    final sectors = [
      for (final cat in person.categories)
        if (cat.category == 'telecom') (cat, telecomWeight * 100),
      for (final cat in person.categories)
        if (cat.category == 'energy') (cat, energyWeight * 100),
    ];
    final shares = <double>[];
    final lines = <Widget>[];
    for (final (cat, sectorPct) in sectors) {
      lines.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${cat.categoryLabel}（${kpiFormatSharePct(sectorPct)}%）',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
        ),
      );
      for (final task in cat.tasks) {
        final w = _taskWeight(task);
        final share = sectorPct * w / 100;
        shares.add(share);
        lines.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              '${task.taskName}：${kpiFormatSharePct(sectorPct)}% × ${kpiFormatSharePct(w)}% = ${kpiFormatSharePct(share)}%',
              style: TextStyle(fontSize: 12, color: text2),
            ),
          ),
        );
      }
    }
    final total = shares.fold<double>(0, (a, b) => a + b);
    return Container(
      key: const Key('kpi-sector-share'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '板块占比',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                auto ? '按营收自动' : '手工设定',
                key: const Key('kpi-sector-share-mode'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: auto
                      ? text3
                      : DunesColors.resolveNullable(context, _accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(_hint, style: TextStyle(fontSize: 12, color: text3)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KpiAdjustField(
                  label: '运营商',
                  hint: '自动 ${kpiFormatSharePct(person.autoTelecomWeight * 100)}%',
                  suffix: '%',
                  controller: telecomCtrl,
                  fieldKey: const Key('kpi-sector-telecom'),
                  enabled: canEdit,
                  onChanged: onTelecomChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _KpiAdjustField(
                  label: '能源',
                  hint: '自动 ${kpiFormatSharePct(person.autoEnergyWeight * 100)}%',
                  suffix: '%',
                  controller: energyCtrl,
                  fieldKey: const Key('kpi-sector-energy'),
                  enabled: canEdit,
                  onChanged: onEnergyChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
              ),
            ],
          ),
          if (canEdit && !auto)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('kpi-sector-reset'),
                onPressed: onResetAuto,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(
                  '恢复按营收自动（运营商 ${kpiFormatSharePct(person.autoTelecomWeight * 100)}% / 能源 ${kpiFormatSharePct(person.autoEnergyWeight * 100)}%）',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                key: const Key('kpi-sector-error'),
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolveNullable(
                    context,
                    const Color(0xFFB42318),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '每条任务最终占比 = 板块占比 × 板块内权重',
            style: TextStyle(fontSize: 12, color: text3),
          ),
          ...lines,
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '合计：${shares.map((v) => '${kpiFormatSharePct(v)}%').join(' + ')} = ${kpiFormatSharePct(total)}%',
              key: const Key('kpi-sector-total'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: (total - 100).abs() > 0.05
                    ? DunesColors.resolveNullable(
                        context,
                        const Color(0xFFB42318),
                      )
                    : text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryEditor extends StatelessWidget {
  const _CategoryEditor({
    required this.category,
    required this.canEdit,
    required this.weightCtrls,
    required this.adjCtrls,
    required this.remarkCtrls,
  });

  final WorkProfileKpiCategory category;
  final bool canEdit;
  final Map<int, TextEditingController> weightCtrls;
  final Map<int, TextEditingController> adjCtrls;
  final Map<int, TextEditingController> remarkCtrls;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${category.categoryLabel}板块 · ${category.tasks.length} 条任务',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                kpiPreviewCategoryScore(
                  category: category,
                  weightCtrls: weightCtrls,
                  adjCtrls: adjCtrls,
                ).toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            category.tasks.length >= 2
                ? '板块分 = 各任务分 × 当月营收占比，合计 ${kpiPreviewCategoryScore(category: category, weightCtrls: weightCtrls, adjCtrls: adjCtrls).toStringAsFixed(2)}'
                : '本板块只有一条任务，权重可改；剩下的比例不计入板块分',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          const SizedBox(height: 10),
          if (canEdit)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                category.tasks.length >= 2
                    ? '未改的任务会按自动权重分摊剩余比例；全部手改时合计须为 100%。'
                    : '改权重后按「任务分 × 权重」计入板块分。',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
              ),
            ),
          for (final task in category.tasks)
            _TaskEditor(
              task: task,
              canEdit: canEdit,
              weightCtrl: weightCtrls[task.taskId]!,
              adjCtrl: adjCtrls[task.taskId]!,
              remarkCtrl: remarkCtrls[task.taskId]!,
            ),
        ],
      ),
    );
  }
}

/// 任务卡：得分怎么来的放在明面上（每个指标的本月/上月、环比、得分与满分），
/// 权重 / 加减分 / 备注三个输入框默认收起，点「调整」才展开——9 条规则时这三个框
/// 会把整页撑到滚不动。
class _TaskEditor extends StatefulWidget {
  const _TaskEditor({
    required this.task,
    required this.canEdit,
    required this.weightCtrl,
    required this.adjCtrl,
    required this.remarkCtrl,
  });

  final WorkProfileKpiTask task;
  final bool canEdit;
  final TextEditingController weightCtrl;
  final TextEditingController adjCtrl;
  final TextEditingController remarkCtrl;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final auto = task.autoWeightPct ?? task.weightPct;
    final weight =
        kpiParseAdjustNum(widget.weightCtrl.text) ?? task.weightPct;
    final adj = kpiParseAdjustNum(widget.adjCtrl.text) ?? task.scoreAdj;
    final previewTotal = kpiPreviewTaskTotal(
      taskTotal: task.taskTotal,
      scoreAdj: task.scoreAdj,
      autoTaskTotal: task.autoTaskTotal,
      adj: adj,
    );
    final touched =
        task.weightOverridden ||
        task.scoreAdjusted ||
        (weight - auto).abs() > 0.05 ||
        (adj - task.scoreAdj).abs() > 0.05;
    final share = (weight / 100).clamp(0.0, 1.0);
    final contribution = kpiWeightedContribution(previewTotal, weight);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFFBFCFC),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            kpiLighthouseSliceTitle(task),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (touched) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: DunesColors.resolve(
                                context,
                                const Color(0xFFF4E8D2),
                                role: DunesColorRole.surface,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              task.scoreAdjusted && !task.weightOverridden
                                  ? '加减分'
                                  : '手工',
                              style: TextStyle(
                                fontSize: 11,
                                color: DunesColors.resolveNullable(
                                  context,
                                  Color(0xFFB07A2B),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kpiLighthouseSliceSubtitle(task),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    previewTotal.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: DunesColors.resolve(context, DunesColors.text),
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '任务分',
                    style: TextStyle(
                      fontSize: 11,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 权重：占比条 + 这条任务实际贡献给板块分多少
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 6,
                    backgroundColor: DunesColors.resolve(
                      context,
                      const Color(0xFFEDEFF2),
                      role: DunesColorRole.surface,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      DunesColors.resolve(context, _accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '权重 ${weight.toStringAsFixed(2)}% · 贡献 ${contribution.toStringAsFixed(1)} 分',
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
            ],
          ),
          if (task.scoreAdjusted) ...[
            const SizedBox(height: 4),
            Text(
              '自动得分 ${(task.autoTaskTotal ?? task.taskTotal).toStringAsFixed(1)} → 现得分 ${task.taskTotal.toStringAsFixed(1)}（${formatKpiAdj(task.scoreAdj)}）',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolveNullable(context, Color(0xFFB07A2B)),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '本月营收 ${kpiMoney(task.curRevenue)} · 上月 ${kpiMoney(task.prevRevenue)}',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          const SizedBox(height: 8),
          KpiMetricList(metrics: task.metrics),
          if (widget.canEdit) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _editing
                  ? FilledButton.icon(
                      key: Key('kpi-edit-${task.taskId}'),
                      onPressed: () => setState(() => _editing = false),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: DunesColors.resolve(
                          context,
                          Colors.white,
                        ),
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                      label: const Text('收起调整'),
                    )
                  : OutlinedButton.icon(
                      key: Key('kpi-edit-${task.taskId}'),
                      onPressed: () => setState(() => _editing = true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        backgroundColor: DunesColors.resolve(
                          context,
                          Colors.white,
                          role: DunesColorRole.surface,
                        ),
                        side: BorderSide(
                          color: DunesColors.resolve(
                            context,
                            Color(0xFFD5E3E7),
                            role: DunesColorRole.border,
                          ),
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('调整权重 / 加减分'),
                    ),
            ),
            if (_editing) ...[
              const SizedBox(height: 10),
              _KpiAdjustPanel(
                taskId: task.taskId,
                autoWeight: auto,
                weightCtrl: widget.weightCtrl,
                adjCtrl: widget.adjCtrl,
                remarkCtrl: widget.remarkCtrl,
              ),
            ],
          ] else if (task.remark.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '备注 ${task.remark}',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolveNullable(context, Color(0xFFB07A2B)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

InputDecoration _kpiAdjustInputDecoration({
  required BuildContext context,
  String? hint,
  String? suffix,
}) {
  const radius = BorderRadius.all(Radius.circular(16));
  const idle = BorderSide(color: Color(0xFFE2E8F0));
  return DunesColors.inputDecoration(
    context,
    InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: DunesColors.text3),
      suffixText: suffix,
      suffixStyle: const TextStyle(fontSize: 12, color: DunesColors.text3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: const OutlineInputBorder(borderRadius: radius, borderSide: idle),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: idle,
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFFEEF1F4)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _accent, width: 1.4),
      ),
    ),
  );
}

class _KpiAdjustPanel extends StatelessWidget {
  const _KpiAdjustPanel({
    required this.taskId,
    required this.autoWeight,
    required this.weightCtrl,
    required this.adjCtrl,
    required this.remarkCtrl,
  });

  final int taskId;
  final double autoWeight;
  final TextEditingController weightCtrl;
  final TextEditingController adjCtrl;
  final TextEditingController remarkCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF4F8F9),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFDCE8EB),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KpiAdjustField(
                  label: '权重',
                  hint: '自动 ${autoWeight.toStringAsFixed(2)}%',
                  suffix: '%',
                  controller: weightCtrl,
                  fieldKey: Key('kpi-weight-$taskId'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _KpiAdjustField(
                  label: '加减分',
                  hint: '正加负减',
                  controller: adjCtrl,
                  fieldKey: Key('kpi-adj-$taskId'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _KpiAdjustField(
            label: '备注',
            hint: '说明调整原因',
            controller: remarkCtrl,
            fieldKey: Key('kpi-remark-$taskId'),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _KpiAdjustField extends StatelessWidget {
  const _KpiAdjustField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.hint,
    this.suffix,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  final ValueChanged<String>? onChanged;
  final String label;
  final String? hint;
  final String? suffix;
  final TextEditingController controller;
  final Key fieldKey;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ),
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled
                ? DunesColors.resolve(context, DunesColors.text)
                : DunesColors.resolve(context, DunesColors.text3),
          ),
          decoration: _kpiAdjustInputDecoration(
            context: context,
            hint: hint,
            suffix: suffix,
          ),
        ),
      ],
    );
  }
}

class _KpiSkipBar extends StatelessWidget {
  const _KpiSkipBar({
    required this.person,
    required this.busy,
    required this.onSkip,
  });

  final WorkProfileKpiPerson person;
  final bool busy;
  final Future<void> Function(String reason) onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '本月不考核',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text2),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kKpiSkipReasons)
              ChoiceChip(
                key: Key('kpi-skip-${option.key}'),
                label: Text(option.value),
                selected: person.skipReason == option.key,
                onSelected: busy
                    ? null
                    : (_) {
                        final next = person.skipReason == option.key
                            ? ''
                            : option.key;
                        unawaited(onSkip(next));
                      },
                selectedColor: DunesColors.resolve(
                  context,
                  DunesColors.brandPurpleSoft,
                ),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: person.skipReason == option.key
                      ? DunesColors.resolve(context, DunesColors.brandPurple)
                      : DunesColors.resolve(context, DunesColors.text2),
                ),
                side: BorderSide(
                  color: person.skipReason == option.key
                      ? DunesColors.resolve(
                          context,
                          DunesColors.brandPurple,
                          role: DunesColorRole.border,
                        ).withValues(alpha: 0.35)
                      : DunesColors.resolve(
                          context,
                          const Color(0xFFE8EAED),
                          role: DunesColorRole.border,
                        ),
                ),
                backgroundColor: DunesColors.resolve(
                  context,
                  Colors.white,
                  role: DunesColorRole.surface,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }
}

/// 顶部：主营分、等级系数，以及运营商/能源两个板块各占多少权重。
/// 没有某个板块的任务时不再显示「运营商 0.0」这种看着像出错的数。
class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.person,
    required this.telecomWeight,
    required this.energyWeight,
    this.manualShare = false,
    this.previewMainScore,
  });

  final WorkProfileKpiPerson person;
  final double telecomWeight;
  final double energyWeight;
  final bool manualShare;
  final double? previewMainScore;

  @override
  Widget build(BuildContext context) {
    final shown = previewMainScore ?? person.mainScore;
    final grade = previewMainScore == null
        ? person.resolvedGrade
        : kpiGradeOf(previewMainScore!);
    final hasTelecom = person.categories.any((c) => c.category == 'telecom');
    final hasEnergy = person.categories.any((c) => c.category == 'energy');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                person.isSkipped
                    ? person.skipLabel
                    : person.isPending
                    ? '未评分'
                    : shown.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, DunesColors.text),
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  person.isRubric ? '量表得分' : '主营得分',
                  style: TextStyle(
                    fontSize: 12,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    person.isSkipped
                        ? '本月不考核'
                        : person.isPending
                        ? '未评分'
                        : grade.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolveNullable(context, _accent),
                    ),
                  ),
                  if (!person.isPending && !person.isSkipped)
                    Text(
                      '系数 ${grade.coefficient}',
                      style: TextStyle(
                        fontSize: 12,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (person.bonus != 0) ...[
            const SizedBox(height: 4),
            Text(
              '含手工加减分 ${formatKpiAdj(person.bonus)}',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolveNullable(context, Color(0xFFB07A2B)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            person.isSkipped
                ? '本月不考核（${person.skipLabel}），转发只带备注，不进均分'
                : person.isRubric
                ? (person.isPending
                      ? '量表未录完必填项，暂不算绩效等级'
                      : '主营分 = 量表各档加总（减分项默认为 0）')
                : hasTelecom && hasEnergy
                ? '主营分 = 运营商 ${person.telecomScore.toStringAsFixed(1)} × ${kpiFormatSharePct(telecomWeight * 100)}% + 能源 ${person.energyScore.toStringAsFixed(1)} × ${kpiFormatSharePct(energyWeight * 100)}%（${manualShare ? '手工设定板块占比' : '按两边当月营收占比'}）'
                : hasEnergy
                ? '只有能源任务，主营分就是能源分'
                : '只有运营商任务，主营分就是运营商分',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ],
      ),
    );
  }
}

class _RubricCategoryEditor extends StatelessWidget {
  const _RubricCategoryEditor({
    required this.category,
    required this.canEdit,
    required this.pointCtrls,
    required this.remarkCtrls,
    this.onChanged,
  });

  final WorkProfileKpiCategory category;
  final bool canEdit;
  final Map<int, TextEditingController> pointCtrls;
  final Map<int, TextEditingController> remarkCtrls;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.categoryLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                category.score.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '对照档位录入分数；未填完必填项不算等级',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          const SizedBox(height: 10),
          for (final task in category.tasks)
            _RubricItemEditor(
              task: task,
              canEdit: canEdit,
              pointCtrl: pointCtrls[task.taskId]!,
              remarkCtrl: remarkCtrls[task.taskId]!,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _RubricItemEditor extends StatelessWidget {
  const _RubricItemEditor({
    required this.task,
    required this.canEdit,
    required this.pointCtrl,
    required this.remarkCtrl,
    this.onChanged,
  });

  final WorkProfileKpiTask task;
  final bool canEdit;
  final TextEditingController pointCtrl;
  final TextEditingController remarkCtrl;
  final VoidCallback? onChanged;

  WorkProfileKpiMetric? get _score =>
      task.metrics.isEmpty ? null : task.metrics.first;

  List<WorkProfileKpiMetric> get _bands =>
      task.metrics.length <= 1 ? const [] : task.metrics.sublist(1);

  String get _rangeHint {
    final m = _score;
    if (m == null) return '';
    if (m.maxPoints == 0 && m.base < 0) {
      return '${m.base.toStringAsFixed(0)}～0';
    }
    return '0～${m.maxPoints.toStringAsFixed(0)}';
  }

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.bucketLabel.isEmpty
                          ? task.taskName
                          : '${task.taskName} · ${task.bucketLabel}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, DunesColors.text),
                      ),
                    ),
                    if (task.matchSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.matchSummary.trim(),
                        style: TextStyle(
                          fontSize: 12,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 88,
                child: TextField(
                  key: Key('kpi-rubric-${task.rubricKey}'),
                  controller: pointCtrl,
                  enabled: canEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  onChanged: (_) => onChanged?.call(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: canEdit
                        ? DunesColors.resolve(context, DunesColors.text)
                        : DunesColors.resolve(context, DunesColors.text3),
                  ),
                  decoration: _kpiAdjustInputDecoration(
                    context: context,
                    hint: _rangeHint,
                    suffix: '分',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: pointCtrl,
            builder: (context, value, _) {
              final pts = double.tryParse(value.text.trim());
              return Column(
                children: [
                  for (final band in _bands)
                    _RubricBandRow(
                      band: band,
                      selected:
                          pts != null &&
                          pts >= band.base &&
                          pts <= band.maxPoints,
                    ),
                ],
              );
            },
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            _KpiAdjustField(
              label: '备注',
              hint: '可选',
              controller: remarkCtrl,
              fieldKey: Key('kpi-rubric-remark-${task.rubricKey}'),
              maxLines: 2,
            ),
          ] else if (task.remark.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.remark,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RubricBandRow extends StatelessWidget {
  const _RubricBandRow({required this.band, required this.selected});

  final WorkProfileKpiMetric band;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: selected
            ? DunesColors.resolve(
                context,
                const Color(0xFFE8F3F6),
                role: DunesColorRole.surface,
              )
            : DunesColors.resolve(
                context,
                const Color(0xFFF7F8FA),
                role: DunesColorRole.surface,
              ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? DunesColors.resolve(
                  context,
                  _accent,
                  role: DunesColorRole.border,
                )
              : DunesColors.resolve(
                  context,
                  const Color(0xFFEDEFF2),
                  role: DunesColorRole.border,
                ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            band.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected
                  ? DunesColors.resolve(context, _accent)
                  : DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          if (band.note.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              band.note,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
