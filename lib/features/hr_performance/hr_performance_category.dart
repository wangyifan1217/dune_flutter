import 'package:flutter/material.dart';
import 'hr_performance_search.dart';
import 'hr_performance_sheets.dart' show hrMaps;
import 'hr_performance_template_ui.dart';

class HrCatalog {
  HrCatalog(Map<String, dynamic> data)
    : departments = hrMaps(data['departments']),
      positions = hrMaps(data['positions']),
      assessmentCategories =
          (data['assessmentCategories'] as List? ?? const [])
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList();
  final List<Map<String, dynamic>> departments, positions;
  final List<String> assessmentCategories;
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

class HrDepartmentNode {
  const HrDepartmentNode({
    required this.id,
    required this.name,
    this.children = const [],
  });
  final int id;
  final String name;
  final List<HrDepartmentNode> children;
}

/// 按 parentId 收成树。上级本身是一个节点，可以直接勾选。
List<HrDepartmentNode> hrDepartmentNodes(
  List<Map<String, dynamic>> departments,
) {
  final ids = <int>{
    for (final raw in departments)
      if (raw['id'] is num) (raw['id'] as num).toInt(),
  };
  final grouped = <int?, List<Map<String, dynamic>>>{};
  for (final raw in departments) {
    if (raw['id'] is! num) continue;
    final parent = raw['parentId'];
    final parentId = parent is num ? parent.toInt() : null;
    final key = parentId != null && ids.contains(parentId) ? parentId : null;
    grouped.putIfAbsent(key, () => []).add(raw);
  }
  final seen = <int>{};
  List<HrDepartmentNode> build(int? parent) => [
    for (final raw in grouped[parent] ?? const <Map<String, dynamic>>[])
      if (seen.add((raw['id'] as num).toInt()))
        HrDepartmentNode(
          id: (raw['id'] as num).toInt(),
          name: '${raw['name']}',
          children: build((raw['id'] as num).toInt()),
        ),
  ];
  final roots = build(null);
  final included = <int>{};
  void mark(HrDepartmentNode node) {
    included.add(node.id);
    for (final child in node.children) {
      mark(child);
    }
  }

  for (final root in roots) {
    mark(root);
  }
  return [
    ...roots,
    for (final raw in departments)
      if (raw['id'] is num && !included.contains((raw['id'] as num).toInt()))
        HrDepartmentNode(
          id: (raw['id'] as num).toInt(),
          name: '${raw['name']}',
        ),
  ];
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
    'categoryNames': (category['categoryNames'] as List? ?? [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(),
  };
}

String hrCategoryLabel(Map<String, dynamic> category, HrCatalog catalog) {
  if (category['mode'] == 'common') return '通用指标';
  if (category['mode'] != 'scoped') return '未分类';
  final deps = (category['departmentIds'] as List).cast<int>();
  final jobs = (category['positionIds'] as List).cast<int>();
  final names = (category['categoryNames'] as List).cast<String>();
  return [
    ...deps.map(catalog.departmentName),
    ...names,
    ...jobs.map((id) => catalog.name(catalog.positions, id)),
  ].join('、');
}

bool hrCategoryMatches(
  Map<String, dynamic> category, {
  int? department,
  String? assessmentCategory,
  HrCatalog? catalog,
}) {
  if (category['mode'] != 'scoped') return true;
  final deps = (category['departmentIds'] as List).cast<int>();
  final names = (category['categoryNames'] as List).cast<String>();
  return (department == null ||
          deps.isEmpty ||
          deps.any(
            (id) =>
                id == department ||
                (catalog != null &&
                    (catalog.departmentWithin(id, department) ||
                        catalog.departmentWithin(department, id))),
          )) &&
      (assessmentCategory == null || names.contains(assessmentCategory));
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
  final collapsed = <int>{};
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.catalog == null
        ? widget.options
              .where(
                (item) => hrPerformanceMatchesSearch(search.text, [
                  '${item['name']}',
                ]),
              )
              .toList()
        : const <Map<String, dynamic>>[];
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
              child: widget.catalog != null
                  ? _DepartmentTreeView(
                      nodes: hrDepartmentNodes(widget.catalog!.departments),
                      query: search.text,
                      collapsed: collapsed,
                      selected: const {},
                      multi: false,
                      onToggleCollapsed: (id) => setState(() {
                        if (!collapsed.remove(id)) collapsed.add(id);
                      }),
                      onToggleSelected: (id) => Navigator.pop(context, id),
                    )
                  : entries.isEmpty
                  ? const Center(child: Text('没有匹配的内容'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final item = entries[index];
                        final id = (item['id'] as num).toInt();
                        return ListTile(
                          title: Text('${item['name']}'),
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
  late Set<String> categories = {
    ...(widget.original['categoryNames'] as List).cast<String>(),
  };
  Future<void> choose(bool department) async {
    if (department) {
      final result = await showHrDepartmentPicker(
        context,
        catalog: widget.catalog,
        selected: departments,
      );
      if (result != null && mounted) setState(() => departments = result);
      return;
    }
    final items = widget.catalog.assessmentCategories;
    final result = await showHrConfigPicker<String>(
      context,
      title: '选择考核分类',
      selected: categories,
      options: [
        for (final name in items) HrConfigOption(name, name),
        for (final name in categories.where((name) => !items.contains(name)))
          HrConfigOption(name, '$name（已移出分类表）'),
      ],
    );
    if (result != null && mounted) setState(() => categories = result);
  }

  Widget modeCard(
    BuildContext context,
    String key,
    String title,
    String detail,
    IconData icon,
  ) {
    final selected = mode == key;
    final accent = hrConfigColor(context, hrConfigPurple);
    final muted = hrConfigColor(context, const Color(0xFF8C8298));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: hrConfigSurface(
          context,
          selected ? const Color(0xFFF4EFFC) : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: hrConfigBorder(
              context,
              selected ? const Color(0xFFCDBBEF) : const Color(0xFFE6E0EE),
            ),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => mode = key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? accent : muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? accent
                              : hrConfigColor(context, const Color(0xFF30263E)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 18,
                  color: selected
                      ? accent
                      : hrConfigBorder(context, const Color(0xFFD5CEDF)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget scopeRow(
    BuildContext context, {
    required bool department,
    required String empty,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final accent = hrConfigColor(context, hrConfigPurple);
    final filled = value.isNotEmpty;
    return Material(
      color: hrConfigSurface(context, const Color(0xFFF7F6FA)),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filled ? value : empty,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: hrConfigColor(
                      context,
                      filled
                          ? const Color(0xFF302B39)
                          : const Color(0xFFA39BAE),
                    ),
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: hrConfigColor(context, const Color(0xFF8C8298)),
              ),
            ],
          ),
        ),
      ),
    );
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
              mode == 'scoped' && departments.isEmpty && categories.isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'mode': mode,
                  'departmentIds': mode == 'scoped'
                      ? departments.toList()
                      : <int>[],
                  'positionIds': <int>[],
                  'categoryNames': mode == 'scoped'
                      ? categories.toList()
                      : <String>[],
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
          modeCard(
            context,
            'uncategorized',
            '未分类',
            '先收入指标库，使用范围以后再定',
            Icons.inbox_outlined,
          ),
          modeCard(
            context,
            'common',
            '通用指标',
            '不限部门、考核分类，配模板时都可以选用',
            Icons.public_outlined,
          ),
          modeCard(
            context,
            'scoped',
            '指定部门 / 考核分类',
            '只在选定的部门或考核分类里出现',
            Icons.account_tree_outlined,
          ),
          if (mode == 'scoped') ...[
            const SizedBox(height: 4),
            const Divider(height: 1, thickness: 1),
            const SizedBox(height: 12),
            scopeRow(
              context,
              department: true,
              empty: '选择部门（可多选）',
              value: departments.isEmpty
                  ? ''
                  : departments.map(widget.catalog.departmentName).join('、'),
              icon: Icons.account_tree_outlined,
              onTap: () => choose(true),
            ),
            const SizedBox(height: 8),
            scopeRow(
              context,
              department: false,
              empty: '选择考核分类（可多选）',
              value: categories.isEmpty ? '' : categories.join('、'),
              icon: Icons.category_outlined,
              onTap: () => choose(false),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '部门或考核分类可只选一项。勾选上级部门时，下级会一起选中。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: hrConfigColor(context, const Color(0xFF8C8298)),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Future<Set<int>?> showHrDepartmentPicker(
  BuildContext context, {
  required HrCatalog catalog,
  required Set<int> selected,
}) => showHrConfigPanel<Set<int>>(
  context,
  _DepartmentPicker(catalog: catalog, initial: selected),
);

class _DepartmentPicker extends StatefulWidget {
  const _DepartmentPicker({required this.catalog, required this.initial});
  final HrCatalog catalog;
  final Set<int> initial;
  @override
  State<_DepartmentPicker> createState() => _DepartmentPickerState();
}

class _DepartmentPickerState extends State<_DepartmentPicker> {
  late final selected = {...widget.initial};
  late final List<HrDepartmentNode> roots = hrDepartmentNodes(
    widget.catalog.departments,
  );
  final byId = <int, HrDepartmentNode>{};
  final parentOf = <int, int>{};
  final collapsed = <int>{};
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    void index(HrDepartmentNode node, int? parent) {
      byId[node.id] = node;
      if (parent != null) parentOf[node.id] = parent;
      for (final child in node.children) {
        index(child, node.id);
      }
    }

    for (final root in roots) {
      index(root, null);
    }
    for (final id in [...selected]) {
      final node = byId[id];
      if (node != null) _addSubtree(node);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _addSubtree(HrDepartmentNode node) {
    selected.add(node.id);
    for (final child in node.children) {
      _addSubtree(child);
    }
  }

  void _removeSubtree(HrDepartmentNode node) {
    selected.remove(node.id);
    for (final child in node.children) {
      _removeSubtree(child);
    }
  }

  bool _subtreeSelected(HrDepartmentNode node) =>
      selected.contains(node.id) && node.children.every(_subtreeSelected);

  void _toggle(int id) {
    final node = byId[id];
    if (node == null) {
      if (!selected.remove(id)) selected.add(id);
      return;
    }
    if (selected.contains(id)) {
      _removeSubtree(node);
      var parent = parentOf[id];
      while (parent != null) {
        selected.remove(parent);
        parent = parentOf[parent];
      }
      return;
    }
    _addSubtree(node);
    var parent = parentOf[id];
    while (parent != null) {
      if (!byId[parent]!.children.every(_subtreeSelected)) break;
      selected.add(parent);
      parent = parentOf[parent];
    }
  }

  /// 整棵子树都选中时只保留上级，避免把每个下级都写进结果。
  Set<int> _compact() {
    final out = <int>{};
    void walk(HrDepartmentNode node) {
      if (_subtreeSelected(node)) {
        out.add(node.id);
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in roots) {
      walk(root);
    }
    for (final id in selected) {
      if (!byId.containsKey(id)) out.add(id);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.catalog.departments
        .map((item) => (item['id'] as num).toInt())
        .toSet();
    final removed = [
      for (final id in selected.where((id) => !known.contains(id)))
        HrDepartmentNode(id: id, name: '已移除 #$id'),
    ];
    return HrConfigPanel(
      title: '选择部门',
      footer: Row(
        children: [
          Expanded(
            child: Text(
              '已选 ${_compact().length} 项',
              style: TextStyle(
                fontSize: 13,
                color: hrConfigColor(context, const Color(0xFF8C8298)),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, _compact()),
            child: const Text('确认选择'),
          ),
        ],
      ),
      child: SizedBox(
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                key: const ValueKey('hr-config-picker-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索部门',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空选择搜索',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(search.clear),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '勾选上级时，下面的部门会一起选中；取消上级时一起取消。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: hrConfigColor(context, const Color(0xFF8C8298)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _DepartmentTreeView(
                nodes: [...roots, ...removed],
                query: search.text,
                collapsed: collapsed,
                selected: selected,
                onToggleCollapsed: (id) => setState(() {
                  if (!collapsed.remove(id)) collapsed.add(id);
                }),
                onToggleSelected: (id) => setState(() => _toggle(id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibleDept {
  const _VisibleDept(this.node, this.depth, this.matched);
  final HrDepartmentNode node;
  final int depth;
  final bool matched;
}

bool _departmentSubtreeMatches(HrDepartmentNode node, String query) {
  if (query.trim().isEmpty) return true;
  if (hrPerformanceMatchesSearch(query, [node.name])) return true;
  return node.children.any((child) => _departmentSubtreeMatches(child, query));
}

List<_VisibleDept> _visibleDepartments(
  List<HrDepartmentNode> nodes,
  String query,
  Set<int> collapsed,
) {
  final out = <_VisibleDept>[];
  void walk(HrDepartmentNode node, int depth, bool ancestorMatched) {
    final self =
        query.trim().isEmpty || hrPerformanceMatchesSearch(query, [node.name]);
    final descendant = node.children.any(
      (child) => _departmentSubtreeMatches(child, query),
    );
    if (query.trim().isNotEmpty && !self && !descendant && !ancestorMatched) {
      return;
    }
    out.add(_VisibleDept(node, depth, self));
    if (query.trim().isEmpty && collapsed.contains(node.id)) return;
    for (final child in node.children) {
      walk(child, depth + 1, ancestorMatched || self);
    }
  }

  for (final node in nodes) {
    walk(node, 0, false);
  }
  return out;
}

class _DepartmentTreeView extends StatelessWidget {
  const _DepartmentTreeView({
    required this.nodes,
    required this.query,
    required this.collapsed,
    required this.selected,
    required this.onToggleCollapsed,
    required this.onToggleSelected,
    this.multi = true,
  });
  final List<HrDepartmentNode> nodes;
  final String query;
  final Set<int> collapsed;
  final Set<int> selected;
  final ValueChanged<int> onToggleCollapsed;
  final ValueChanged<int> onToggleSelected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleDepartments(nodes, query, collapsed);
    if (visible.isEmpty) return const Center(child: Text('没有匹配的内容'));
    final accent = hrConfigColor(context, hrConfigPurple);
    final muted = hrConfigColor(context, const Color(0xFF8C8298));
    final line = hrConfigBorder(context, const Color(0xFFE4DEEC));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 12),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final row = visible[index];
        final node = row.node;
        final on = selected.contains(node.id);
        return Column(
          children: [
            if (row.depth == 0 && index > 0)
              Divider(height: 12, thickness: 1, color: line),
            InkWell(
              key: ValueKey('hr-option-${node.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onToggleSelected(node.id),
              child: Padding(
                padding: EdgeInsets.only(left: row.depth * 22.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 36,
                      child: node.children.isEmpty
                          ? null
                          : IconButton(
                              key: ValueKey('hr-dept-toggle-${node.id}'),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: collapsed.contains(node.id)
                                  ? '展开${node.name}'
                                  : '收起${node.name}',
                              onPressed: () => onToggleCollapsed(node.id),
                              icon: Icon(
                                query.trim().isNotEmpty ||
                                        !collapsed.contains(node.id)
                                    ? Icons.expand_more_rounded
                                    : Icons.chevron_right_rounded,
                                size: 18,
                                color: muted,
                              ),
                            ),
                    ),
                    if (multi)
                      Icon(
                        on
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: on ? accent : muted,
                      ),
                    if (multi) const SizedBox(width: 8),
                    if (row.depth > 0)
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.only(right: 8),
                        color: line,
                      ),
                    Expanded(
                      child: Text(
                        node.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: row.depth == 0
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: on || (row.matched && query.trim().isNotEmpty)
                              ? accent
                              : hrConfigColor(context, const Color(0xFF30263E)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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
  String? assessmentCategory;
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
                assessmentCategory: assessmentCategory,
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
                    label: assessmentCategory ?? '全部考核分类',
                    onTap: () async {
                      final names = widget.catalog.assessmentCategories;
                      final current = assessmentCategory == null
                          ? null
                          : names.indexOf(assessmentCategory!) + 1;
                      final value = await hrChooseFilter(context, '选择考核分类', [
                        for (var i = 0; i < names.length; i++)
                          {'id': i + 1, 'name': names[i]},
                      ], current == 0 ? null : current);
                      if (!mounted) return;
                      setState(() {
                        assessmentCategory = value == null
                            ? null
                            : names[value - 1];
                      });
                    },
                    onClear: assessmentCategory == null
                        ? null
                        : () => setState(() => assessmentCategory = null),
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
