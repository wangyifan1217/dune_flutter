import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import 'kpi_metric_list.dart';
import 'workbench_kpi_service.dart';

const _accent = Color(0xFF3D7A8C);

class WorkbenchKpiDetailPane extends StatefulWidget {
  const WorkbenchKpiDetailPane({
    super.key,
    required this.personName,
    required this.monthLabel,
    required this.score,
    required this.canEdit,
    this.busy = false,
    this.onSave,
  });

  final String personName;
  final String monthLabel;
  final WorkProfileKpiScore score;
  final bool canEdit;
  final bool busy;
  final Future<void> Function(List<WorkbenchKpiOverrideItem> items, String summary)?
      onSave;

  @override
  State<WorkbenchKpiDetailPane> createState() => _WorkbenchKpiDetailPaneState();
}

class _WorkbenchKpiDetailPaneState extends State<WorkbenchKpiDetailPane> {
  final Map<int, TextEditingController> _weightCtrls = {};
  final Map<int, TextEditingController> _adjCtrls = {};
  final Map<int, TextEditingController> _remarkCtrls = {};

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
    super.dispose();
  }

  void _syncControllers() {
    final seen = <int>{};
    for (final task in _allTasks()) {
      seen.add(task.taskId);
      _weightCtrls.putIfAbsent(task.taskId, () => TextEditingController()).text =
          task.weightPct.toStringAsFixed(2);
      _adjCtrls.putIfAbsent(task.taskId, () => TextEditingController()).text =
          task.scoreAdj == 0 ? '0' : formatKpiAdj(task.scoreAdj);
      _remarkCtrls.putIfAbsent(task.taskId, () => TextEditingController()).text =
          task.remark;
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
      final weightChanged = canAdjustWeight &&
          parsed != null &&
          (parsed - auto).abs() > 0.05;
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
          const SizedBox(height: 4),
          const SizedBox(height: 8),
          _ScoreHeader(person: person),
          const SizedBox(height: 12),
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

InputDecoration _kpiAdjustInputDecoration({
  String? hint,
  String? suffix,
}) {
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
    enabledBorder: const OutlineInputBorder(borderRadius: radius, borderSide: idle),
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
                  hint: lockWeight ? '该板块仅一项，无法改比例' : '自动 ${autoWeight.toStringAsFixed(2)}%',
                  suffix: '%',
                  controller: weightCtrl,
                  fieldKey: Key('kpi-weight-$taskId'),
                  enabled: !lockWeight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

/// 顶部：主营分、等级系数，以及通信/能源两个板块各占多少权重。
/// 没有某个板块的任务时不再显示「通信 0.0」这种看着像出错的数。
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
                person.mainScore.toStringAsFixed(2),
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
                  '主营得分',
                  style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    grade.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
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
            hasTelecom && hasEnergy
                ? '主营分 = 通信 ${person.telecomScore.toStringAsFixed(1)} × ${(person.telecomWeight * 100).toStringAsFixed(0)}% + 能源 ${person.energyScore.toStringAsFixed(1)} × ${(person.energyWeight * 100).toStringAsFixed(0)}%（按两边当月营收占比）'
                : hasEnergy
                    ? '只有能源板块任务，主营分就是能源板块分'
                    : '只有通信板块任务，主营分就是通信板块分',
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
          ),
        ],
      ),
    );
  }
}
