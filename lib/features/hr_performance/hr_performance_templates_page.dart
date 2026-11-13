import 'dart:convert';
import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_service.dart';
import 'hr_performance_sheet.dart';

class HrPerformanceTemplatesPage extends StatefulWidget {
  const HrPerformanceTemplatesPage({
    super.key,
    required this.session,
    required this.service,
    required this.onBack,
    this.loadContacts,
  });
  final AuthSession session;
  final HrPerformanceService service;
  final VoidCallback onBack;
  final Future<ContactOrgData> Function()? loadContacts;
  @override
  State<HrPerformanceTemplatesPage> createState() => _State();
}

class _State extends State<HrPerformanceTemplatesPage> {
  int version = 0;
  bool loading = true, saving = false;
  String? error;
  String departmentQuery = '', userQuery = '';
  List<Map<String, dynamic>> templates = [], indicators = [];
  List<NativeDepartment> departments = [];
  List<NativeContact> users = [];
  Map<String, dynamic>? editing;
  List<Map<String, dynamic>> maps(dynamic v) => (v is List ? v : [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.service.templates();
      final org =
          await (widget.loadContacts?.call() ??
              ContactService(session: widget.session).fetchOrgContacts());
      final deps = <NativeDepartment>[], people = <NativeContact>[];
      void walk(NativeDepartment d) {
        deps.add(d);
        people.addAll(d.users);
        for (final c in d.children) {
          walk(c);
        }
      }

      for (final d in org.departments) {
        walk(d);
      }
      if (!mounted) return;
      setState(() {
        version = (data['version'] as num).toInt();
        templates = maps(data['templates']);
        indicators = maps(data['indicators']);
        departments = deps;
        users = people.where((u) => u.enabled).toList();
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  void edit(Map<String, dynamic>? value, {bool copy = false}) {
    final draft = value == null
        ? <String, dynamic>{
            'id': 'template-${DateTime.now().microsecondsSinceEpoch}',
            'name': '',
            'keywords': <String>[],
            'priority': 10,
            'scoreMode': 'direct',
            'enabled': true,
            'items': <dynamic>[],
            'departmentIds': <int>[],
            'userIds': <int>[],
          }
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
    if (copy) {
      draft['id'] = 'template-${DateTime.now().microsecondsSinceEpoch}';
      draft['name'] = '${draft['name']}（副本）';
      draft['enabled'] = false;
      draft['departmentIds'] = <int>[];
      draft['userIds'] = <int>[];
      draft['keywords'] = <String>[];
    }
    final materialized = maps(draft['items']);
    for (final item in materialized) {
      if (item['snapshot'] == null) {
        final matches = indicators.where((i) => i['id'] == item['indicatorId']);
        if (matches.isNotEmpty) {
          item['snapshot'] = jsonDecode(jsonEncode(matches.first));
        }
      }
    }
    draft['items'] = materialized;
    draft['departmentIds'] ??= <int>[];
    draft['userIds'] ??= <int>[];
    draft['keywords'] ??= <String>[];
    setState(() => editing = draft);
  }

  InputDecoration itemDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF7F6F9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF8060D4), width: 1.2),
    ),
  );

  Future<void> editItem(
    Map<String, dynamic> template,
    String indicatorId,
  ) async {
    final items = maps(template['items']);
    final index = items.indexWhere(
      (item) => item['indicatorId'] == indicatorId,
    );
    if (index < 0) return;
    final item = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(items[index])) as Map,
    );
    final snapshot = Map<String, dynamic>.from(item['snapshot'] as Map);
    final bands = maps(snapshot['bands']);
    final initialWeight = item['weight'];
    final result = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('编辑 ${snapshot['name']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: '$initialWeight',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: itemDecoration('本模板指标权重（%）'),
                    onChanged: (v) => item['weight'] = double.tryParse(v) ?? 0,
                  ),
                  TextFormField(
                    initialValue: '${snapshot['instructions'] ?? ''}',
                    maxLines: 3,
                    decoration: itemDecoration('本模板评分说明'),
                    onChanged: (v) => snapshot['instructions'] = v,
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('评分分档')),
                      IconButton(
                        tooltip: '添加模板分档',
                        onPressed: () => update(
                          () => bands.add({
                            'min': 0.0,
                            'max': 0.0,
                            'description': '',
                          }),
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  for (var j = 0; j < bands.length; j++)
                    Padding(
                      key: ObjectKey(bands[j]),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: '${bands[j]['min']}',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: itemDecoration('最低分'),
                                  onChanged: (v) =>
                                      bands[j]['min'] = double.tryParse(v),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: '${bands[j]['max']}',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: itemDecoration('最高分'),
                                  onChanged: (v) =>
                                      bands[j]['max'] = double.tryParse(v),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除模板分档',
                                onPressed: () =>
                                    update(() => bands.removeAt(j)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          TextFormField(
                            initialValue: '${bands[j]['description']}',
                            maxLines: 3,
                            decoration: itemDecoration('评分标准'),
                            onChanged: (v) => bands[j]['description'] = v,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: '取消模板指标编辑',
              onPressed: () => Navigator.pop(dialog, false),
              icon: const Icon(Icons.close_rounded),
            ),
            IconButton.filled(
              tooltip: '完成模板指标编辑',
              onPressed: () {
                final weight = (item['weight'] as num?)?.toDouble() ?? 0;
                if (weight <= 0 ||
                    weight > 100 ||
                    bands.any((b) {
                      final min = (b['min'] as num?)?.toDouble();
                      final max = (b['max'] as num?)?.toDouble();
                      return min == null ||
                          max == null ||
                          !min.isFinite ||
                          !max.isFinite ||
                          min < 0 ||
                          max < min ||
                          max >
                              (template['scoreMode'] == 'direct'
                                  ? weight
                                  : 100) ||
                          '${b['description'] ?? ''}'.trim().isEmpty;
                    })) {
                  showDunesToast(context, '请核对权重及分档范围，分档不得超过该指标满分');
                  return;
                }
                snapshot['bands'] = bands;
                item['snapshot'] = snapshot;
                Navigator.pop(dialog, true);
              },
              icon: const Icon(Icons.check_rounded),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    setState(() {
      final current = maps(template['items']);
      final currentIndex = current.indexWhere(
        (v) => v['indicatorId'] == indicatorId,
      );
      if (currentIndex >= 0) {
        current[currentIndex] = item;
        template['items'] = current;
      }
    });
  }

  Future<void> save() async {
    final d = editing!;
    final items = maps(d['items']);
    final weight = items.fold<double>(
      0,
      (n, e) => n + ((e['weight'] as num?)?.toDouble() ?? 0),
    );
    if ('${d['name']}'.trim().isEmpty || (weight - 100).abs() > .00001) {
      showDunesToast(context, '请填写模板名称，指标权重合计须为 100%');
      return;
    }
    final next = [...templates];
    final index = next.indexWhere((t) => t['id'] == d['id']);
    if (index < 0) {
      next.add(d);
    } else {
      next[index] = d;
    }
    setState(() => saving = true);
    try {
      final res = await widget.service.saveTemplates(version, next);
      if (!mounted) return;
      setState(() {
        version = (res['version'] as num).toInt();
        templates = maps(res['templates']);
        indicators = maps(res['indicators']);
        editing = null;
      });
      showDunesToast(context, '考核模板已保存');
    } catch (e) {
      if (mounted) showDunesToast(context, '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!),
            TextButton(
              onPressed: () {
                setState(() => loading = true);
                load();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    final d = editing;
    return Material(
      color: const Color(0xFFF7F4FC),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: d == null
                    ? widget.onBack
                    : () => setState(() => editing = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  d == null ? '考核模板' : '编辑考核模板',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (d == null)
                FilledButton.icon(
                  onPressed: () => edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('新建模板'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (d == null) ...[
            const Text('分别组装指标并选择适用范围。指定人员优先于部门，已有考核周期保持原快照。'),
            const SizedBox(height: 12),
            for (final t in templates)
              Card(
                child: ListTile(
                  title: Text('${t['name']}'),
                  subtitle: Text(
                    '${maps(t['items']).length} 项指标 · ${t['enabled'] == true ? '启用' : '停用'}',
                  ),
                  trailing: IconButton(
                    tooltip: '复制模板',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () => edit(t, copy: true),
                  ),
                  onTap: () => edit(t),
                ),
              ),
          ],
          if (d != null) ...[
            TextFormField(
              key: ValueKey('name-${d['id']}'),
              initialValue: '${d['name']}',
              decoration: const InputDecoration(labelText: '模板名称'),
              onChanged: (v) => d['name'] = v,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用模板'),
              value: d['enabled'] == true,
              onChanged: (v) => setState(() => d['enabled'] = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('按指标分值直接计分'),
              subtitle: const Text('开启后各项实际得分相加；关闭后每项按百分制评分并乘以权重。只影响新生成的考核。'),
              value: d['scoreMode'] == 'direct',
              onChanged: (v) =>
                  setState(() => d['scoreMode'] = v ? 'direct' : ''),
            ),
            const Text(
              '从指标库选择指标，并设置本模板的权重',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final i in indicators.where(
              (i) =>
                  i['enabled'] == true ||
                  maps(d['items']).any((x) => x['indicatorId'] == i['id']),
            ))
              Builder(
                builder: (context) {
                  final items = maps(d['items']);
                  final idx = items.indexWhere(
                    (x) => x['indicatorId'] == i['id'],
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Checkbox(
                            value: idx >= 0,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                items.add({
                                  'indicatorId': i['id'],
                                  'weight': i['weight'],
                                  'snapshot': jsonDecode(jsonEncode(i)),
                                });
                              } else {
                                items.removeAt(idx);
                              }
                              d['items'] = items;
                            }),
                          ),
                          Expanded(
                            child: Text('${i['project']} · ${i['name']}'),
                          ),
                          if (idx >= 0)
                            IconButton(
                              tooltip: '编辑模板指标',
                              icon: const Icon(Icons.tune_rounded),
                              onPressed: () => editItem(d, '${i['id']}'),
                            ),
                          if (idx >= 0)
                            Text(
                              '${items[idx]['weight']}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Text(
              '指标权重合计：${maps(d['items']).fold<double>(0, (n, item) => n + ((item['weight'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text('考核表预览', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            HrAssessmentSheet(
              lines: [
                for (final item in maps(d['items']))
                  for (final indicator in indicators.where(
                    (v) => v['id'] == item['indicatorId'],
                  ))
                    {
                      ...indicator,
                      if (item['snapshot'] is Map)
                        ...Map<String, dynamic>.from(item['snapshot'] as Map),
                      'weight': item['weight'],
                      'directScore': d['scoreMode'] == 'direct',
                    },
              ],
            ),
            const SizedBox(height: 16),
            const Text('适用部门', style: TextStyle(fontWeight: FontWeight.w700)),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索部门',
              ),
              onChanged: (v) => setState(() => departmentQuery = v.trim()),
            ),
            for (final dep in departments.where(
              (v) => v.name.contains(departmentQuery),
            ))
              CheckboxListTile(
                dense: true,
                title: Text(dep.name),
                value: (d['departmentIds'] as List).contains(dep.id),
                onChanged: (v) => setState(() {
                  final ids = List<dynamic>.from(d['departmentIds']);
                  if (v == true) {
                    ids.add(dep.id);
                  } else {
                    ids.remove(dep.id);
                  }
                  d['departmentIds'] = ids;
                }),
              ),
            const SizedBox(height: 12),
            const Text(
              '指定人员（优先于部门）',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索姓名或部门',
              ),
              onChanged: (v) => setState(() => userQuery = v.trim()),
            ),
            for (final u in users.where(
              (v) =>
                  v.displayName.contains(userQuery) ||
                  (v.department ?? '').contains(userQuery),
            ))
              CheckboxListTile(
                dense: true,
                title: Text(u.displayName),
                subtitle: Text(u.department ?? ''),
                value: (d['userIds'] as List).contains(u.userId),
                onChanged: (v) => setState(() {
                  final ids = List<dynamic>.from(d['userIds']);
                  if (v == true) {
                    ids.add(u.userId);
                  } else {
                    ids.remove(u.userId);
                  }
                  d['userIds'] = ids;
                }),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? '保存中' : '保存模板'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
