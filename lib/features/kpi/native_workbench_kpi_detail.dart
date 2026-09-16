import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import 'kpi_metric_list.dart';
import 'workbench_kpi_service.dart';

const _accent = DunesColors.brandPurple;

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
  String? _rubricError;

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
      c.dispose();
    }
    for (final c in _adjCtrls.values) {
      c.dispose();
    }
    for (final c in _remarkCtrls.values) {
      c.dispose();
    }
    for (final c in _pointCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    final seen = <int>{};
    for (final task in _allTasks()) {
      seen.add(task.taskId);
      _weightCtrls
          .putIfAbsent(task.taskId, () => TextEditingController())
          .text = task.weightPct.toStringAsFixed(
        2,
      );
      _adjCtrls.putIfAbsent(task.taskId, () => TextEditingController()).text =
          task.scoreAdj == 0 ? '0' : formatKpiAdj(task.scoreAdj);
      _remarkCtrls
              .putIfAbsent(task.taskId, () => TextEditingController())
              .text =
          task.remark;
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
      ctrl.dispose();
      return true;
    });
    _adjCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.dispose();
      return true;
    });
    _remarkCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.dispose();
      return true;
    });
    _pointCtrls.removeWhere((id, ctrl) {
      if (seen.contains(id)) return false;
      ctrl.dispose();
      return true;
    });
  }

  List<WorkProfileKpiTask> _allTasks() {
    final person = _person;
    if (person == null) return const [];
    return [for (final cat in person.categories) ...cat.tasks];
  }

  Map<int, int> _categorySize() {
    final sizes = <int, int>{};
    for (final cat in _person?.categories ?? const <WorkProfileKpiCategory>[]) {
      for (final task in cat.tasks) {
        sizes[task.taskId] = cat.tasks.length;
      }
    }
    return sizes;
  }

  List<WorkbenchKpiOverrideItem> _collectItems() {
    final sizes = _categorySize();
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
      final canAdjustWeight = (sizes[task.taskId] ?? 0) >= 2;
      final weightChanged =
          canAdjustWeight && parsed != null && (parsed - auto).abs() > 0.05;
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

  String _confirmSummary(List<WorkbenchKpiOverrideItem> items) {
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
    return '${widget.personName} ${widget.monthLabel}\n${lines.join('\n')}';
  }

  Future<void> _submit() async {
    final onSave = widget.onSave;
    if (onSave == null || widget.busy) return;
    final items = _collectItems();
    final summary = items.isEmpty
        ? '${widget.personName} ${widget.monthLabel}\n将清空手工权重、加减分和备注，恢复自动计算。'
        : _confirmSummary(items);
    await onSave(items, summary);
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
      return const Center(
        child: Text('该月暂无计入绩效明细', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.personName} · ${widget.monthLabel}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: DunesColors.text,
            ),
          ),
          if (person.isRubric && person.scoredByName.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '考核人 ${person.scoredByName}',
              key: const Key('kpi-scored-by'),
              style: const TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
          ],
          if (person.isRubric && person.isAcked) ...[
            const SizedBox(height: 4),
            Text(
              '被考核人已确认 ${formatKpiAckedAt(person.ackedAt)}',
              key: const Key('kpi-acked'),
              style: const TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
          ] else if (person.isRubric && person.isUnpublished) ...[
            const SizedBox(height: 4),
            const Text(
              '尚未发布到绩效助手',
              key: Key('kpi-unpublished'),
              style: TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
          ],
          const SizedBox(height: 8),
          _ScoreHeader(person: person),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB42318),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
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
                category.score.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            category.tasks.length >= 2
                ? '板块分 = 各任务分 × 当月营收占比，合计 ${category.score.toStringAsFixed(2)}'
                : '本板块只有一条任务，板块分就是它的任务分',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 10),
          if (canEdit && category.tasks.length >= 2)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '未改的任务会按自动权重分摊剩余比例；全部手改时合计须为 100%。',
                style: TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ),
          for (final task in category.tasks)
            _TaskEditor(
              task: task,
              canEdit: canEdit,
              lockWeight: category.tasks.length < 2,
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
    required this.lockWeight,
    required this.weightCtrl,
    required this.adjCtrl,
    required this.remarkCtrl,
  });

  final WorkProfileKpiTask task;
  final bool canEdit;
  final bool lockWeight;
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
    final touched = task.weightOverridden || task.scoreAdjusted;
    final share = (task.weightPct / 100).clamp(0.0, 1.0);
    final contribution = task.taskTotal * task.weightPct / 100;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
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
                              color: const Color(0xFFF4E8D2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              task.scoreAdjusted && !task.weightOverridden
                                  ? '加减分'
                                  : '手工',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB07A2B),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
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
                    task.taskTotal.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: DunesColors.text,
                      height: 1.1,
                    ),
                  ),
                  const Text(
                    '任务分',
                    style: TextStyle(fontSize: 11, color: DunesColors.text3),
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
                    backgroundColor: const Color(0xFFEDEFF2),
                    valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '权重 ${task.weightPct.toStringAsFixed(2)}% · 贡献 ${contribution.toStringAsFixed(1)} 分',
                style: const TextStyle(fontSize: 12, color: DunesColors.text2),
              ),
            ],
          ),
          if (task.scoreAdjusted) ...[
            const SizedBox(height: 4),
            Text(
              '自动得分 ${(task.autoTaskTotal ?? task.taskTotal).toStringAsFixed(1)} → 现得分 ${task.taskTotal.toStringAsFixed(1)}（${formatKpiAdj(task.scoreAdj)}）',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB07A2B)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '本月营收 ${kpiMoney(task.curRevenue)} · 上月 ${kpiMoney(task.prevRevenue)}',
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
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
                        foregroundColor: Colors.white,
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
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFD5E3E7)),
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
                lockWeight: widget.lockWeight,
                weightCtrl: widget.weightCtrl,
                adjCtrl: widget.adjCtrl,
                remarkCtrl: widget.remarkCtrl,
              ),
            ],
          ] else if (task.remark.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '备注 ${task.remark}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB07A2B)),
            ),
          ],
        ],
      ),
    );
  }
}

InputDecoration _kpiAdjustInputDecoration({String? hint, String? suffix}) {
  const radius = BorderRadius.all(Radius.circular(16));
  const idle = BorderSide(color: Color(0xFFE2E8F0));
  return InputDecoration(
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
  );
}

class _KpiAdjustPanel extends StatelessWidget {
  const _KpiAdjustPanel({
    required this.taskId,
    required this.autoWeight,
    required this.lockWeight,
    required this.weightCtrl,
    required this.adjCtrl,
    required this.remarkCtrl,
  });

  final int taskId;
  final double autoWeight;
  final bool lockWeight;
  final TextEditingController weightCtrl;
  final TextEditingController adjCtrl;
  final TextEditingController remarkCtrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE8EB)),
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
                  hint: lockWeight
                      ? '该板块仅一项，无法改比例'
                      : '自动 ${autoWeight.toStringAsFixed(2)}%',
                  suffix: '%',
                  controller: weightCtrl,
                  fieldKey: Key('kpi-weight-$taskId'),
                  enabled: !lockWeight,
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
  });

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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? DunesColors.text : DunesColors.text3,
          ),
          decoration: _kpiAdjustInputDecoration(hint: hint, suffix: suffix),
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
        const Text(
          '本月不考核',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
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
                selectedColor: DunesColors.brandPurpleSoft,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: person.skipReason == option.key
                      ? DunesColors.brandPurple
                      : DunesColors.text2,
                ),
                side: BorderSide(
                  color: person.skipReason == option.key
                      ? DunesColors.brandPurple.withValues(alpha: 0.35)
                      : const Color(0xFFE8EAED),
                ),
                backgroundColor: Colors.white,
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
  const _ScoreHeader({required this.person});

  final WorkProfileKpiPerson person;

  @override
  Widget build(BuildContext context) {
    final grade = person.resolvedGrade;
    final hasTelecom = person.categories.any((c) => c.category == 'telecom');
    final hasEnergy = person.categories.any((c) => c.category == 'energy');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
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
                    : person.mainScore.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.text,
                  height: 1.05,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  person.isRubric ? '量表得分' : '主营得分',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                  if (!person.isPending && !person.isSkipped)
                    Text(
                      '系数 ${grade.coefficient}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DunesColors.text3,
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
              style: const TextStyle(fontSize: 12, color: Color(0xFFB07A2B)),
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
                ? '主营分 = 运营商 ${person.telecomScore.toStringAsFixed(1)} × ${(person.telecomWeight * 100).toStringAsFixed(0)}% + 能源 ${person.energyScore.toStringAsFixed(1)} × ${(person.energyWeight * 100).toStringAsFixed(0)}%（按两边当月营收占比）'
                : hasEnergy
                ? '只有能源任务，主营分就是能源分'
                : '只有运营商任务，主营分就是运营商分',
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DunesColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '对照档位录入分数；未填完必填项不算等级',
            style: TextStyle(fontSize: 12, color: DunesColors.text3),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                    if (task.matchSummary.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        task.matchSummary.trim(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
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
                    color: canEdit ? DunesColors.text : DunesColors.text3,
                  ),
                  decoration: _kpiAdjustInputDecoration(
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
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
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
        color: selected ? const Color(0xFFE8F3F6) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? _accent : const Color(0xFFEDEFF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            band.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? _accent : DunesColors.text2,
            ),
          ),
          if (band.note.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              band.note,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ],
        ],
      ),
    );
  }
}
