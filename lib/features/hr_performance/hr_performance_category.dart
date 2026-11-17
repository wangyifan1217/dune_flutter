import 'package:flutter/material.dart';
import 'hr_performance_search.dart';
import 'hr_performance_sheets.dart' show hrMaps;
import 'hr_performance_template_ui.dart';

class HrCatalog {
  HrCatalog(Map<String, dynamic> data)
    : departments = hrMaps(data['departments']),
      positions = hrMaps(data['positions']);
  final List<Map<String, dynamic>> departments, positions;
  String name(List<Map<String, dynamic>> list, int id) =>
      list.where((e) => e['id'] == id).map((e) => '${e['name']}').firstOrNull ??
      '已移除 #$id';
  bool departmentWithin(int child, int ancestor) {
    final seen = <int>{};
    int? current = child;
    while (current != null && seen.add(current)) {
      if (current == ancestor) return true;
      final found = departments.where((entry) => entry['id'] == current);
      if (found.isEmpty) break;
      current = (found.first['parentId'] as num?)?.toInt();
    }
    return false;
  }

  String departmentName(int id) {
    final names = <String>[];
    final seen = <int>{};
    int? current = id;
    while (current != null && seen.add(current)) {
      final entries = departments.where((e) => e['id'] == current);
      if (entries.isEmpty) {
        if (names.isEmpty) names.add('已移除 #$id');
        break;
      }
      final entry = entries.first;
      names.insert(0, '${entry['name']}');
      current = (entry['parentId'] as num?)?.toInt();
    }
    return names.join(' / ');
  }
}

Map<String, dynamic> hrCategory(dynamic value) {
  final category = value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};
  return {
    'mode': category['mode'] ?? 'uncategorized',
    'departmentIds': (category['departmentIds'] as List? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList(),
    'positionIds': (category['positionIds'] as List? ?? [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList(),
  };
}

String hrCategoryLabel(Map<String, dynamic> category, HrCatalog catalog) {
  if (category['mode'] == 'common') return '通用指标';
  if (category['mode'] != 'scoped') return '未分类';
  final deps = (category['departmentIds'] as List).cast<int>();
  final jobs = (category['positionIds'] as List).cast<int>();
  return [
    ...deps.map(catalog.departmentName),
    ...jobs.map((id) => catalog.name(catalog.positions, id)),
  ].join('、');
}

bool hrCategoryMatches(
  Map<String, dynamic> category, {
  int? department,
  int? position,
  HrCatalog? catalog,
}) {
  if (category['mode'] != 'scoped') return true;
  final deps = (category['departmentIds'] as List).cast<int>();
  final jobs = (category['positionIds'] as List).cast<int>();
  return (department == null ||
          deps.isEmpty ||
          deps.any(
            (id) =>
                id == department ||
                (catalog != null &&
                    (catalog.departmentWithin(id, department) ||
                        catalog.departmentWithin(department, id))),
          )) &&
      (position == null || jobs.isEmpty || jobs.contains(position));
}

Future<int?> hrChooseFilter(
  BuildContext context,
  String title,
  List<Map<String, dynamic>> options,
  int? selected, {
  HrCatalog? catalog,
}) async {
  final value = await showHrConfigPanel<int>(
    context,
    _SingleFilter(title: title, options: options, catalog: catalog),
  );
  return value == null
      ? selected
      : value == -1
      ? null
      : value;
}

class _SingleFilter extends StatefulWidget {
  const _SingleFilter({
    required this.title,
    required this.options,
    this.catalog,
  });
  final String title;
  final List<Map<String, dynamic>> options;
  final HrCatalog? catalog;
  @override
  State<_SingleFilter> createState() => _SingleFilterState();
}

class _SingleFilterState extends State<_SingleFilter> {
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.options
        .where(
          (item) => hrPerformanceMatchesSearch(search.text, [
            widget.catalog == null
                ? '${item['name']}'
                : widget.catalog!.departmentName((item['id'] as num).toInt()),
          ]),
        )
        .toList();
    return HrConfigPanel(
      title: widget.title,
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索${widget.title.replaceFirst('选择', '')}',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            ListTile(
              title: const Text('全部'),
              onTap: () => Navigator.pop(context, -1),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('没有匹配的内容'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final id = (item['id'] as num).toInt();
                        return ListTile(
                          title: Text(
                            widget.catalog == null
                                ? '${item['name']}'
                                : widget.catalog!.departmentName(id),
                          ),
                          onTap: () => Navigator.pop(context, id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showHrCategoryEditor(
  BuildContext context,
  HrCatalog catalog,
  Map<String, dynamic> original,
) => showHrConfigPanel<Map<String, dynamic>>(
  context,
  _CategoryEditor(catalog: catalog, original: original),
);

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.catalog, required this.original});
  final HrCatalog catalog;
  final Map<String, dynamic> original;
  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late String mode = '${widget.original['mode']}';
  late Set<int> departments = {
    ...(widget.original['departmentIds'] as List).cast<int>(),
  };
  late Set<int> positions = {
    ...(widget.original['positionIds'] as List).cast<int>(),
  };
  Future<void> choose(bool department) async {
    final items = department
        ? widget.catalog.departments
        : widget.catalog.positions;
    final current = department ? departments : positions;
    final result = await showHrConfigPicker<int>(
      context,
      title: department ? '选择部门' : '选择岗位',
      selected: current,
      options: [
        for (final e in items)
          HrConfigOption(
            (e['id'] as num).toInt(),
            department
                ? widget.catalog.departmentName((e['id'] as num).toInt())
                : '${e['name']}',
          ),
        for (final id in current.where(
          (id) => !items.any((e) => e['id'] == id),
        ))
          HrConfigOption(id, '已移除 #$id'),
      ],
    );
    if (result != null && mounted) {
      setState(() {
        if (department) {
          departments = result;
        } else {
          positions = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => HrConfigPanel(
    title: '设置指标分类',
    footer: Row(
      children: [
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed:
              mode == 'scoped' && departments.isEmpty && positions.isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'mode': mode,
                  'departmentIds': mode == 'scoped'
                      ? departments.toList()
                      : <int>[],
                  'positionIds': mode == 'scoped'
                      ? positions.toList()
                      : <int>[],
                }),
          child: const Text('确定'),
        ),
      ],
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final e in const {
                'uncategorized': '未分类',
                'common': '通用指标',
                'scoped': '指定部门 / 岗位',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: mode == e.key,
                  onSelected: (_) => setState(() => mode = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (mode == 'scoped') ...[
            OutlinedButton.icon(
              onPressed: () => choose(true),
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                departments.isEmpty
                    ? '选择部门（可多选）'
                    : '部门：${departments.map(widget.catalog.departmentName).join('、')}',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => choose(false),
              icon: const Icon(Icons.badge_outlined),
              label: Text(
                positions.isEmpty
                    ? '选择岗位（可多选）'
                    : '岗位：${positions.map((id) => widget.catalog.name(widget.catalog.positions, id)).join('、')}',
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '部门或岗位可只选一项；同时选择时按两项筛选。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class HrFilterButton extends StatelessWidget {
  const HrFilterButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onClear,
  });
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final active = onClear != null;
    final accent = hrConfigColor(context, hrConfigPurple);
    final muted = hrConfigColor(context, const Color(0xFF746C80));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 48,
      ),
      child: InputChip(
        label: Text(label, overflow: TextOverflow.ellipsis),
        labelStyle: TextStyle(
          color: active ? accent : muted,
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
        avatar: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: active ? accent : muted,
        ),
        backgroundColor: hrConfigSurface(
          context,
          active ? const Color(0xFFF0EAFB) : Colors.white,
        ),
        side: BorderSide(
          color: hrConfigBorder(
            context,
            active ? const Color(0xFFCDBBEF) : const Color(0xFFE5DDEF),
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        onPressed: onTap,
        onDeleted: onClear,
        deleteIcon: Icon(Icons.close_rounded, size: 16, color: accent),
      ),
    );
  }
}

Future<Set<String>?> showHrIndicatorPicker(
  BuildContext context, {
  required HrCatalog catalog,
  required List<Map<String, dynamic>> indicators,
  required Set<String> selected,
  int? department,
}) => showHrConfigPanel<Set<String>>(
  context,
  _IndicatorPicker(
    catalog: catalog,
    indicators: indicators,
    selected: selected,
    department: department,
  ),
  maxWidth: 720,
);

class _IndicatorPicker extends StatefulWidget {
  const _IndicatorPicker({
    required this.catalog,
    required this.indicators,
    required this.selected,
    this.department,
  });
  final HrCatalog catalog;
  final List<Map<String, dynamic>> indicators;
  final Set<String> selected;
  final int? department;
  @override
  State<_IndicatorPicker> createState() => _IndicatorPickerState();
}

class _IndicatorPickerState extends State<_IndicatorPicker> {
  late Set<String> selected = {...widget.selected};
  late int? department = widget.department;
  int? position;
  String? dimension;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.indicators
        .where(
          (i) =>
              (i['enabled'] == true ||
                  widget.selected.contains('${i['id']}')) &&
              (dimension == null || i['project'] == dimension) &&
              hrCategoryMatches(
                hrCategory(i['category']),
                department: department,
                position: position,
                catalog: widget.catalog,
              ) &&
              hrPerformanceMatchesSearch(search.text, [
                '${i['name']}',
                '${i['project']}',
                '${i['instructions']}',
                ...hrMaps(i['bands']).map((b) => '${b['description']}'),
              ]),
        )
        .toList();
    final dimensions = widget.indicators
        .map((i) => '${i['project'] ?? ''}')
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();
    return HrConfigPanel(
      title: '选择考核指标',
      footer: Row(
        children: [
          Expanded(child: Text('已选 ${selected.length} 项')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('确认选择'),
          ),
        ],
      ),
      child: SizedBox(
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                key: const ValueKey('hr-config-picker-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索指标、维度或评分说明',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  HrFilterButton(
                    label: department == null
                        ? '全部部门'
                        : widget.catalog.departmentName(department!),
                    onTap: () async {
                      final value = await hrChooseFilter(
                        context,
                        '选择部门',
                        widget.catalog.departments,
                        department,
                        catalog: widget.catalog,
                      );
                      if (mounted) setState(() => department = value);
                    },
                    onClear: department == null
                        ? null
                        : () => setState(() => department = null),
                  ),
                  HrFilterButton(
                    label: position == null
                        ? '全部岗位'
                        : widget.catalog.name(
                            widget.catalog.positions,
                            position!,
                          ),
                    onTap: () async {
                      final value = await hrChooseFilter(
                        context,
                        '选择岗位',
                        widget.catalog.positions,
                        position,
                      );
                      if (mounted) setState(() => position = value);
                    },
                    onClear: position == null
                        ? null
                        : () => setState(() => position = null),
                  ),
                  HrFilterButton(
                    label: dimension ?? '全部维度',
                    onTap: () async {
                      final current = dimension == null
                          ? null
                          : dimensions.indexOf(dimension!) + 1;
                      final result = await hrChooseFilter(context, '选择维度', [
                        for (var i = 0; i < dimensions.length; i++)
                          {'id': i + 1, 'name': dimensions[i]},
                      ], current);
                      if (mounted) {
                        setState(
                          () => dimension = result == null
                              ? null
                              : dimensions[result - 1],
                        );
                      }
                    },
                    onClear: dimension == null
                        ? null
                        : () => setState(() => dimension = null),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('没有匹配的指标'))
                  : ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (ctx, index) {
                        final i = visible[index];
                        final id = '${i['id']}';
                        final category = hrCategory(i['category']);
                        final instructions = '${i['instructions'] ?? ''}'
                            .trim();
                        final bands = hrMaps(i['bands']);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              key: ValueKey('hr-option-$id'),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: selected.contains(id),
                              title: Text(
                                '${i['name']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${i['project']} · 默认权重 ${i['weight']}% · ${hrCategoryLabel(category, widget.catalog)}',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }),
                            ),
                            if (instructions.isNotEmpty || bands.isNotEmpty)
                              ExpansionTile(
                                tilePadding: const EdgeInsets.fromLTRB(
                                  56,
                                  0,
                                  16,
                                  0,
                                ),
                                visualDensity: VisualDensity.compact,
                                title: const Text(
                                  '评分说明',
                                  style: TextStyle(fontSize: 12),
                                ),
                                children: [
                                  if (instructions.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        56,
                                        0,
                                        16,
                                        8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          instructions,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  for (final band in bands)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        56,
                                        0,
                                        16,
                                        8,
                                      ),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '${band['min']}–${band['max']} · ${band['description']}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
