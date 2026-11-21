import 'package:flutter/material.dart';

import 'hr_performance_service.dart';
import 'hr_performance_sheets.dart';

Future<Map<String, dynamic>?> showHrSupervisorSheet(
  BuildContext context,
  List<Map<String, dynamic>> users, {
  String? scope,
}) => hrFormSheet(
  context,
  title: '修改本月考核主管',
  message: '${scope == null ? '' : '$scope\n'}仅调整所列人员本月考核的主管。已完成审批保留，如需重审请回退。',
  values: {'reason': ''},
  fields: (v, update) => [
    if (users.isEmpty) const Text('未获取到可选的组织用户，请刷新后重试。'),
    for (final direct in [true, false]) ...[
      if (users.isNotEmpty)
        HrSelect<int>(
          key: ValueKey((
            direct,
            v[direct ? 'resetDirectSupervisor' : 'resetDivisionSupervisor'] ==
                true,
          )),
          decoration: InputDecoration(labelText: direct ? '直属主管' : '分管主管'),
          initialValue:
              v[direct ? 'directSupervisorId' : 'divisionSupervisorId'] as int?,
          searchHint: '搜索姓名、部门、岗位或用户编号',
          items: [
            for (final user in users)
              if (user['id'] is num)
                DropdownMenuItem(
                  value: (user['id'] as num).toInt(),
                  child: Text(
                    [
                      hrText(user['name']),
                      if (hrText(user['department']).isNotEmpty)
                        hrText(user['department']),
                      if (hrText(user['position']).isNotEmpty)
                        hrText(user['position']),
                      '#${user['id']}',
                    ].join(' · '),
                  ),
                ),
          ],
          onChanged: (id) => update(() {
            v[direct ? 'directSupervisorId' : 'divisionSupervisorId'] = id;
            v.remove(
              direct ? 'resetDirectSupervisor' : 'resetDivisionSupervisor',
            );
          }),
        ),
      CheckboxListTile(
        dense: true,
        title: const Text('恢复跟随组织关系'),
        value:
            v[direct ? 'resetDirectSupervisor' : 'resetDivisionSupervisor'] ==
            true,
        onChanged: (checked) => update(() {
          v[direct ? 'resetDirectSupervisor' : 'resetDivisionSupervisor'] =
              checked;
          if (checked == true) {
            v.remove(direct ? 'directSupervisorId' : 'divisionSupervisorId');
          }
        }),
      ),
    ],
    hrReasonField(v),
  ],
  submit: (v) {
    if (hrText(v['reason']).isEmpty) throw const FormatException('请填写修改原因');
    if (v['directSupervisorId'] == null &&
        v['divisionSupervisorId'] == null &&
        v['resetDirectSupervisor'] != true &&
        v['resetDivisionSupervisor'] != true) {
      throw const FormatException('请选择主管或恢复组织关系');
    }
    return v;
  },
);

Future<Map<String, dynamic>?> showHrExportSheet(
  BuildContext context, {
  required List<HrPerformanceRecord> records,
  required List<Map<String, dynamic>> departments,
  required Set<int> selectedIds,
  required String month,
  bool forForward = false,
}) {
  final selected = {...selectedIds};
  final departmentIds = <int>{};
  var mode = 'people';
  var descendants = true;
  var query = '';
  Set<int> includedDepartments() {
    final ids = {...departmentIds};
    if (descendants) {
      bool changed;
      do {
        changed = false;
        for (final d in departments) {
          if (ids.contains(d['parentId']) &&
              ids.add((d['id'] as num).toInt())) {
            changed = true;
          }
        }
      } while (changed);
    }
    return ids;
  }

  List<HrPerformanceRecord> targets() {
    final ids = includedDepartments();
    return records
        .where(
          (r) => mode == 'people'
              ? selected.contains(r.id)
              : ids.contains(r.departmentId),
        )
        .toList();
  }

  return hrFormSheet(
    context,
    title: '${forForward ? '选择转发范围' : '导出考核表'} · $month',
    confirmSubmission: !forForward,
    maxWidth: 680,
    confirmationMessage: () =>
        '月份：$month\n范围：${mode == 'people' ? '按人员' : '按部门${descendants ? '（含下级部门）' : ''}'}\n共 ${targets().length} 人：${targets().map((r) => '${r.name}（${r.department}）').join('、')}\n每人一张 Sheet。',
    submitLabel: forForward ? '选择会话' : '导出 Excel',
    message: forForward
        ? '可选择部门或多位人员；将按当前权限范围选择考核表。'
        : '一个 Excel 工作簿，每人一张 Sheet。部门模式按完整部门导出，不受列表筛选限制。',
    values: {},
    fields: (v, update) => [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'people', label: Text('按人员')),
          ButtonSegment(value: 'department', label: Text('按部门')),
        ],
        selected: {mode},
        onSelectionChanged: (s) => update(() {
          mode = s.first;
          query = '';
        }),
      ),
      TextField(
        key: ValueKey('hr-export-search-$mode'),
        decoration: InputDecoration(
          labelText: mode == 'people' ? '搜索姓名、部门、岗位' : '搜索部门',
        ),
        onChanged: (s) => update(() => query = s.trim()),
      ),
      if (mode == 'department')
        CheckboxListTile(
          title: const Text('包含下级部门'),
          value: descendants,
          onChanged: (b) => update(() => descendants = b == true),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '将${forForward ? '转发' : '导出'} ${targets().length} 人${mode == 'department' ? ' · 已选 ${departmentIds.length} 个部门' : ''}',
        ),
      ),
      if (mode == 'people')
        for (final r in records.where(
          (r) => '${r.name} ${r.department} ${r.position}'.contains(query),
        ))
          CheckboxListTile(
            dense: true,
            title: Text(r.name),
            subtitle: Text('${r.department} · ${r.position}'),
            value: selected.contains(r.id),
            onChanged: (b) => update(() {
              if (b == true) {
                selected.add(r.id);
              } else {
                selected.remove(r.id);
              }
            }),
          )
      else
        for (final d in departments.where(
          (d) => '${d['name']}'.contains(query),
        ))
          CheckboxListTile(
            dense: true,
            title: Text('${d['name']}'),
            value: departmentIds.contains(d['id']),
            onChanged: (b) => update(() {
              final id = (d['id'] as num).toInt();
              if (b == true) {
                departmentIds.add(id);
              } else {
                departmentIds.remove(id);
              }
            }),
          ),
    ],
    submit: (_) {
      if (targets().isEmpty) throw const FormatException('所选范围没有考核表');
      if (forForward) return {'ids': targets().map((r) => r.id).toList()};
      return mode == 'people'
          ? {'ids': selected.toList()}
          : {
              'departmentIds': departmentIds.toList(),
              'includeDescendants': descendants,
            };
    },
  );
}

class HrInlineDeductionEditor extends StatefulWidget {
  const HrInlineDeductionEditor({super.key, required this.onSave});
  final Future<void> Function(double points, String reason) onSave;
  @override
  State<HrInlineDeductionEditor> createState() =>
      _HrInlineDeductionEditorState();
}

class _HrInlineDeductionEditorState extends State<HrInlineDeductionEditor> {
  final points = TextEditingController();
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    points.dispose();
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: points,
        decoration: const InputDecoration(
          labelText: '扣分（正数；0 表示不扣分）',
          isDense: true,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      TextField(
        controller: reason,
        decoration: const InputDecoration(labelText: '扣分原因及来源', isDense: true),
        minLines: 1,
        maxLines: 3,
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: busy
              ? null
              : () async {
                  final value = double.tryParse(points.text);
                  if (value == null ||
                      !value.isFinite ||
                      value < 0 ||
                      (value > 0 && reason.text.trim().isEmpty)) {
                    setState(() => error = '请填写有效扣分及原因');
                    return;
                  }
                  if (value == 0) {
                    setState(() => error = null);
                    return;
                  }
                  if (!await hrConfirmAction(
                    context,
                    title: '保存扣分',
                    message:
                        '扣分：$value\n原因及来源：${reason.text.trim()}\n确认后计入本次绩效。',
                  )) {
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.onSave(value, reason.text.trim());
                    if (mounted) {
                      points.clear();
                      reason.clear();
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = '$e');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(busy ? '保存中…' : '保存扣分'),
        ),
      ),
    ],
  );
}
