import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
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
          Text(
            person.bonus == 0
                ? '主营 ${person.mainScore.toStringAsFixed(2)}  · 通信 ${person.telecomScore.toStringAsFixed(1)}  · 能源 ${person.energyScore.toStringAsFixed(1)}'
                : '主营 ${person.mainScore.toStringAsFixed(2)}  · 加减分 ${formatKpiAdj(person.bonus)}  · 通信 ${person.telecomScore.toStringAsFixed(1)}  · 能源 ${person.energyScore.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 13, color: DunesColors.text2),
          ),
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
          Text(
            '${category.categoryLabel}（${category.tasks.length}）· 得分 ${category.score.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
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

class _TaskEditor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final auto = task.autoWeightPct ?? task.weightPct;
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (task.weightOverridden || task.scoreAdjusted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4E8D2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    task.scoreAdjusted && !task.weightOverridden ? '加减分' : '手工',
                    style: const TextStyle(fontSize: 11, color: Color(0xFFB07A2B)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            task.scoreAdjusted
                ? '自动权重 ${auto.toStringAsFixed(2)}% · 自动得分 ${(task.autoTaskTotal ?? task.taskTotal).toStringAsFixed(1)} · 现得分 ${task.taskTotal.toStringAsFixed(1)}（${formatKpiAdj(task.scoreAdj)}）'
                : '自动权重 ${auto.toStringAsFixed(2)}% · 得分 ${task.taskTotal.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          Text(
            '本月收入 ${formatKpiNum(task.curRevenue)} · 上月 ${formatKpiNum(task.prevRevenue)}',
            style: const TextStyle(fontSize: 12, color: DunesColors.text2),
          ),
          Text(
            task.metrics.map((m) => m.line).join('；'),
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            TextField(
              key: Key('kpi-weight-${task.taskId}'),
              controller: weightCtrl,
              enabled: canEdit && !lockWeight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: lockWeight ? '任务权重 %（该板块仅一项，无法改比例）' : '任务权重 %',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('kpi-adj-${task.taskId}'),
              controller: adjCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              decoration: const InputDecoration(
                isDense: true,
                labelText: '加减分',
                hintText: '正数为加分，负数为减分',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('kpi-remark-${task.taskId}'),
              controller: remarkCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '备注',
                hintText: '说明为什么调整权重或分数',
                border: OutlineInputBorder(),
              ),
            ),
          ] else if (task.remark.isNotEmpty) ...[
            const SizedBox(height: 4),
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
