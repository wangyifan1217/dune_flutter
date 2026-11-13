import 'package:flutter/material.dart';

import '../contacts/contact_models.dart';
import 'hr_performance_service.dart';

List<Map<String, dynamic>> hrMaps(dynamic value) =>
    (value is List ? value : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
double hrNumber(dynamic value) {
  final v = double.tryParse('$value');
  if (v == null || !v.isFinite) throw const FormatException('请填写有效数字');
  return v;
}

String hrText(dynamic v) => '${v ?? ''}'.trim();

Future<Map<String, dynamic>?> hrFormSheet(
  BuildContext context, {
  required String title,
  required Map<String, dynamic> values,
  required List<Widget> Function(Map<String, dynamic>, StateSetter) fields,
  required Map<String, dynamic> Function(Map<String, dynamic>) submit,
  String submitLabel = '提交',
  String? message,
}) {
  String? error;
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 800),
    builder: (context) => StatefulBuilder(
      builder: (context, update) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(message),
                        ),
                      ...fields(values, update),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const ValueKey('hr-sheet-submit'),
                  onPressed: () {
                    try {
                      final result = submit(values);
                      Navigator.pop(context, result);
                    } on FormatException catch (e) {
                      update(() => error = e.message);
                    } catch (e) {
                      update(() => error = '$e');
                    }
                  },
                  child: Text(submitLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget hrReasonField(
  Map<String, dynamic> values, {
  String label = '说明 / 理由',
  String keyName = 'reason',
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: TextFormField(
    key: ValueKey('hr-$keyName'),
    initialValue: hrText(values[keyName]),
    minLines: 2,
    maxLines: 5,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    onChanged: (v) => values[keyName] = v,
  ),
);

Future<Map<String, dynamic>?> showHrReasonSheet(
  BuildContext context, {
  required String title,
  String? message,
  List<String>? targets,
  int minLength = 0,
  String submitLabel = '确认',
}) => hrFormSheet(
  context,
  title: title,
  message: message,
  submitLabel: submitLabel,
  values: {'reason': '', 'target': targets?.first},
  fields: (v, update) => [
    if (targets != null)
      _HrSelect<String>(
        initialValue: hrText(v['target']),
        decoration: const InputDecoration(labelText: '处理方式'),
        items: targets
            .map(
              (x) => DropdownMenuItem(
                value: x,
                child: Text(
                  hrPerformanceStageLabels[x] ?? (x == 'reject' ? '驳回申诉' : x),
                ),
              ),
            )
            .toList(),
        onChanged: (x) => update(() => v['target'] = x),
      ),
    hrReasonField(v),
  ],
  submit: (v) {
    if (hrText(v['reason']).runes.length < minLength) {
      throw FormatException('说明至少 $minLength 个字');
    }
    return {
      'reason': hrText(v['reason']),
      if (targets != null) 'target': v['target'],
    };
  },
);

Future<Map<String, dynamic>?> showHrScoreSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> config, {
  required String title,
  required bool initial,
}) {
  final lines = [
    for (final line in record.lines)
      {
        ...line,
        'score': '${line['score'] ?? line['suggestedScore'] ?? ''}',
        'remark': '${line['remark'] ?? ''}',
      },
  ];
  final rules = Map<String, dynamic>.from(config['rules'] as Map? ?? {});
  return hrFormSheet(
    context,
    title: title,
    values: {'lines': lines, 'reason': ''},
    submitLabel: initial ? '提交初评' : '保存并提交',
    message: initial
        ? '按每项满分填写得分；无建议分、与建议分不一致或低于备注线时须填写备注。'
        : '改动任何分数都须填写改分理由。',
    fields: (v, update) => [
      for (final line in lines)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line['name']} · 权重 ${line['weight']}%'),
                Text('建议分：${line['suggestedScore'] ?? '无'}'),
                for (final band in hrMaps(line['bands']))
                  Text(
                    '${band['min']}–${band['max']} 分：${band['description']}',
                  ),
                TextFormField(
                  key: ValueKey('hr-score-${line['indicatorId']}'),
                  initialValue: hrText(line['score']),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '指标得分'),
                  onChanged: (x) => update(() => line['score'] = x),
                ),
                if (initial)
                  TextFormField(
                    key: ValueKey('hr-remark-${line['indicatorId']}'),
                    initialValue: hrText(line['remark']),
                    decoration: const InputDecoration(labelText: '评分备注'),
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (x) => line['remark'] = x,
                  ),
              ],
            ),
          ),
        ),
      Text(
        '指标得分：${lines.fold<double>(0, (n, l) => n + (double.tryParse('${l['score']}') ?? 0) * (l['directScore'] == true ? 1 : ((l['weight'] as num?)?.toDouble() ?? 0) / 100)).toStringAsFixed(1)}；本月加减分：${record.bonuses.fold<double>(0, (n, b) => n + ((b['points'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)}',
      ),
      if (!initial) hrReasonField(v, label: '改分理由（改动时必填）'),
    ],
    submit: (v) {
      final result = <Map<String, dynamic>>[];
      for (final l in lines) {
        final score = hrNumber(l['score']);
        final maxScore = l['directScore'] == true
            ? ((l['weight'] as num?)?.toDouble() ?? 0)
            : 100.0;
        if (score < 0 || score > maxScore) {
          throw FormatException('指标分须为 0–$maxScore');
        }
        final decimal = (rules['decimalPlaces'] as num?)?.toInt() ?? 1;
        final multiplier = decimal == 0 ? 1 : 10;
        if ((score * multiplier - (score * multiplier).round()).abs() >
            0.00001) {
          throw FormatException('最多 $decimal 位小数');
        }
        if (initial &&
            (l['suggestedScore'] == null ||
                (hrNumber(l['suggestedScore']) - score).abs() > 0.00001 ||
                (l['directScore'] == true && maxScore > 0
                        ? score * 100 / maxScore
                        : score) <
                    ((rules['remarkBelow'] as num?)?.toDouble() ?? 60)) &&
            hrText(l['remark']).isEmpty) {
          throw FormatException('${l['name']}须填写评分备注');
        }
        result.add({
          'indicatorId': l['indicatorId'],
          'score': score,
          'remark': hrText(l['remark']),
        });
      }
      if (!initial &&
          lines.any((l) {
            final old = record.lines.firstWhere(
              (x) => x['indicatorId'] == l['indicatorId'],
            );
            return old['score'] != hrNumber(l['score']);
          }) &&
          hrText(v['reason']).isEmpty) {
        throw const FormatException('请填写改分理由');
      }
      return {'lines': result, 'reason': hrText(v['reason'])};
    },
  );
}

Future<Map<String, dynamic>?> showHrAdjustmentSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> options,
) {
  final config = Map<String, dynamic>.from(options['config'] as Map);
  final library = hrMaps(config['indicators']);
  final indicators = <String, Map<String, dynamic>>{
    for (final i in library) '${i['id']}': i,
  };
  for (final l in record.lines) {
    indicators.putIfAbsent(
      '${l['indicatorId']}',
      () => {
        'id': l['indicatorId'],
        'name': l['name'],
        'enabled': false,
        'weight': l['weight'],
      },
    );
  }
  final weights = <String, String>{
    for (final l in record.lines) '${l['indicatorId']}': '${l['weight']}',
  };
  final taskMap = <int, Map<String, dynamic>>{
    for (final t in [...record.evidence, ...hrMaps(options['tasks'])])
      (t['id'] as num).toInt(): t,
  };
  final selected = record.evidence.map((t) => (t['id'] as num).toInt()).toSet();
  return hrFormSheet(
    context,
    title: '申请调整考核指标与任务',
    values: {'reason': ''},
    message: '一次只能有一条待审批申请。主管通过前，原考核表保持不变。',
    fields: (v, update) => [
      for (final i in indicators.values)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${i['name']}'),
                  subtitle: i['enabled'] != true
                      ? const Text('指标已停用，现有快照可保留')
                      : null,
                  value: weights.containsKey('${i['id']}'),
                  onChanged:
                      i['enabled'] != true && !weights.containsKey('${i['id']}')
                      ? null
                      : (checked) => update(() {
                          if (checked == true) {
                            weights['${i['id']}'] = '${i['weight'] ?? 0}';
                          } else {
                            weights.remove('${i['id']}');
                          }
                        }),
                ),
                if (weights.containsKey('${i['id']}'))
                  TextFormField(
                    key: ValueKey('hr-weight-${i['id']}'),
                    initialValue: weights['${i['id']}'],
                    decoration: const InputDecoration(labelText: '权重 %'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (x) => update(() => weights['${i['id']}'] = x),
                  ),
              ],
            ),
          ),
        ),
      Text(
        '权重合计 ${weights.values.fold<double>(0, (a, b) => a + (double.tryParse(b) ?? 0)).toStringAsFixed(1)}%',
        key: const ValueKey('hr-weight-total'),
      ),
      const Divider(),
      const Text('任务证据（仅本人在考核月完成的任务）'),
      for (final e in taskMap.entries)
        CheckboxListTile(
          title: Text('${e.value['title']}'),
          value: selected.contains(e.key),
          onChanged: (x) => update(() {
            if (x == true) {
              selected.add(e.key);
            } else {
              selected.remove(e.key);
            }
          }),
        ),
      hrReasonField(v, label: '调整原因（必填）'),
    ],
    submit: (v) {
      final total = weights.values.fold<double>(0, (a, b) => a + hrNumber(b));
      if ((total - 100).abs() > 0.00001) {
        throw const FormatException('权重合计必须为 100%');
      }
      if (hrText(v['reason']).isEmpty) throw const FormatException('请填写调整原因');
      return {
        'reason': hrText(v['reason']),
        'lines': [
          for (final e in weights.entries)
            {'indicatorId': e.key, 'weight': hrNumber(e.value)},
        ],
        'evidenceIds': selected.toList(),
      };
    },
  );
}

Future<Map<String, dynamic>?> showHrBonusSheet(
  BuildContext context,
  Map<String, dynamic> config,
) {
  final items = hrMaps(
    config['adjustmentItems'],
  ).where((i) => i['enabled'] == true).toList();
  if (items.isEmpty) return Future.value(null);
  return hrFormSheet(
    context,
    title: '录入本月加减分',
    values: {
      'itemId': items.first['id'],
      'points': '${items.first['points']}',
      'source': '',
    },
    fields: (v, update) => [
      _HrSelect<String>(
        initialValue: '${v['itemId']}',
        items: items
            .map(
              (i) => DropdownMenuItem(
                value: '${i['id']}',
                child: Text(
                  '${i['name']} · ${i['direction'] == 'add' ? '加分' : '扣分'}',
                ),
              ),
            )
            .toList(),
        onChanged: (x) => update(() => v['itemId'] = x),
      ),
      TextFormField(
        initialValue: '${v['points']}',
        decoration: const InputDecoration(labelText: '分值（正数）'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (x) => v['points'] = x,
      ),
      hrReasonField(
        v,
        label:
            items.firstWhere((i) => i['id'] == v['itemId'])['requireSource'] ==
                true
            ? '来源说明（必填）'
            : '来源说明（选填）',
        keyName: 'source',
      ),
    ],
    submit: (v) {
      if (hrNumber(v['points']) <= 0 ||
          (items.firstWhere((i) => i['id'] == v['itemId'])['requireSource'] ==
                  true &&
              hrText(v['source']).isEmpty)) {
        throw const FormatException('请填写正数分值和来源说明');
      }
      return {
        'itemId': v['itemId'],
        'points': hrNumber(v['points']),
        'source': hrText(v['source']),
      };
    },
  );
}

Future<Map<String, dynamic>?> showHrAssignmentSheet(
  BuildContext context,
  HrPerformanceRecord record,
  Map<String, dynamic> config,
  List<NativeContact> contacts, {
  List<Map<String, dynamic>> departments = const [],
  List<Map<String, dynamic>> positions = const [],
}) => hrFormSheet(
  context,
  title: '补配本周期考核表',
  message: '仅修改本周期快照。请同时核对组织用户里的岗位与汇报关系，避免下月再次缺失。',
  values: {'reason': ''},
  fields: (v, update) => [
    if (['opening', 'indicators'].contains(record.stage)) ...[
      _HrSelect<int>(
        decoration: InputDecoration(labelText: '部门（当前：${record.department}）'),
        items: departments
            .map(
              (d) => DropdownMenuItem(
                value: (d['id'] as num).toInt(),
                child: Text('${d['name']}'),
              ),
            )
            .toList(),
        onChanged: (x) => v['departmentId'] = x,
      ),
      _HrSelect<int>(
        decoration: InputDecoration(labelText: '岗位（当前：${record.position}）'),
        items: positions
            .map(
              (d) => DropdownMenuItem(
                value: (d['id'] as num).toInt(),
                child: Text('${d['name']}'),
              ),
            )
            .toList(),
        onChanged: (x) => v['positionId'] = x,
      ),
      TextFormField(
        initialValue: hrText(record.snapshot['hiredAt']),
        decoration: const InputDecoration(labelText: '入职日期（YYYY-MM-DD，未修改则保持）'),
        onChanged: (x) => v['hiredAt'] = x,
      ),
      TextFormField(
        initialValue: hrText(record.snapshot['probationEndAt']),
        decoration: const InputDecoration(labelText: '试用期截止（YYYY-MM-DD，可清空）'),
        onChanged: (x) => v['probationEndAt'] = x,
      ),
      _HrSelect<String>(
        decoration: const InputDecoration(labelText: '本周期模板（留空保持）'),
        items: hrMaps(config['templates'])
            .where((t) => t['enabled'] == true)
            .map(
              (t) => DropdownMenuItem(
                value: '${t['id']}',
                child: Text('${t['name']}'),
              ),
            )
            .toList(),
        onChanged: (x) => v['templateId'] = x,
      ),
    ],
    _HrSelect<int>(
      decoration: const InputDecoration(labelText: '直属主管（留空保持）'),
      items: contacts
          .where((u) => u.enabled && u.userId != record.userId)
          .map(
            (u) =>
                DropdownMenuItem(value: u.userId, child: Text(u.displayName)),
          )
          .toList(),
      onChanged: (x) => v['directSupervisorId'] = x,
    ),
    _HrSelect<int>(
      decoration: const InputDecoration(labelText: '分管主管（留空保持）'),
      items: contacts
          .where((u) => u.enabled)
          .map(
            (u) =>
                DropdownMenuItem(value: u.userId, child: Text(u.displayName)),
          )
          .toList(),
      onChanged: (x) => v['divisionSupervisorId'] = x,
    ),
    hrReasonField(v),
  ],
  submit: (v) {
    if (hrText(v['reason']).isEmpty) throw const FormatException('请填写修改原因');
    if ([
      'templateId',
      'directSupervisorId',
      'divisionSupervisorId',
      'departmentId',
      'positionId',
      'hiredAt',
      'probationEndAt',
    ].every((key) => v[key] == null)) {
      throw const FormatException('请选择要补配的内容');
    }
    return v;
  },
);

/// 与绩效弹层统一的单选入口，长名单支持搜索。
class _HrSelect<T> extends StatefulWidget {
  const _HrSelect({
    this.initialValue,
    this.decoration = const InputDecoration(),
    required this.items,
    required this.onChanged,
  });
  final T? initialValue;
  final InputDecoration decoration;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  @override
  State<_HrSelect<T>> createState() => _HrSelectState<T>();
}

class _HrSelectState<T> extends State<_HrSelect<T>> {
  T? value;
  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  Future<void> choose() async {
    String query = '';
    final selected = await showModalBottomSheet<DropdownMenuItem<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final choices = widget.items.where((item) {
            final child = item.child;
            final label = child is Text ? (child.data ?? '') : '';
            return query.isEmpty ||
                label.toLowerCase().contains(query.toLowerCase());
          }).toList();
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜索',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => update(() => query = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in choices)
                        ListTile(
                          title: item.child,
                          trailing: item.value == value
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, item),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => value = selected.value);
    widget.onChanged(selected.value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((item) => item.value == value).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: choose,
        child: InputDecorator(
          decoration: widget.decoration.copyWith(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: const Icon(Icons.expand_more_rounded),
          ),
          child: selected.isEmpty
              ? const Text('请选择', style: TextStyle(color: Colors.grey))
              : selected.first.child,
        ),
      ),
    );
  }
}
