import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'hr_performance_search.dart';
import 'hr_performance_service.dart';
import 'hr_performance_sheet.dart';
import 'hr_performance_template_item_editor.dart';
import 'hr_performance_template_ui.dart';

class HrPerformanceTemplatesPage extends StatefulWidget {
  const HrPerformanceTemplatesPage({
    super.key,
    required this.session,
    required this.service,
    required this.onBack,
    this.loadContacts,
    this.listBackTooltip = '返回指标库',
  });
  final AuthSession session;
  final HrPerformanceService service;
  final VoidCallback onBack;
  final Future<ContactOrgData> Function()? loadContacts;
  final String listBackTooltip;
  @override
  State<HrPerformanceTemplatesPage> createState() => _State();
}

class _State extends State<HrPerformanceTemplatesPage> {
  late final _avatars = ConversationService(session: widget.session);
  int version = 0;
  bool loading = true, saving = false;
  String? error;
  final templateSearch = TextEditingController();
  final indicatorSearch = TextEditingController();
  List<Map<String, dynamic>> templates = [], indicators = [];
  List<NativeDepartment> departments = [];
  List<NativeContact> users = [];
  Map<String, dynamic>? editing;
  String initialDraft = '';
  List<Map<String, dynamic>> maps(dynamic v) => (v is List ? v : [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    templateSearch.dispose();
    indicatorSearch.dispose();
    super.dispose();
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
        users = {
          for (final u in people.where((u) => u.enabled)) u.userId: u,
        }.values.toList();
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
    indicatorSearch.clear();
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
    final items = maps(draft['items']);
    for (final item in items) {
      if (item['snapshot'] == null) {
        final source = indicators.where((i) => i['id'] == item['indicatorId']);
        if (source.isNotEmpty) {
          item['snapshot'] = jsonDecode(jsonEncode(source.first));
        }
      }
    }
    draft['items'] = items;
    draft['departmentIds'] ??= <int>[];
    draft['userIds'] ??= <int>[];
    draft['keywords'] ??= <String>[];
    initialDraft = jsonEncode(draft);
    setState(() => editing = draft);
  }

  Future<void> leave() async {
    if (saving) return;
    if (editing == null) {
      widget.onBack();
      return;
    }
    if (jsonEncode(editing) != initialDraft) {
      final discard = await showHrConfigPanel<bool>(
        context,
        Builder(
          builder: (ctx) => HrConfigPanel(
            title: '放弃本次修改？',
            footer: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续编辑'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('放弃修改'),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text('本次修改尚未保存，返回后将丢失。'),
            ),
          ),
        ),
        maxWidth: 420,
      );
      if (discard != true || !mounted) return;
    }
    setState(() => editing = null);
  }

  Map<String, dynamic> effective(Map<String, dynamic> item) {
    if (item['snapshot'] is Map) {
      return Map<String, dynamic>.from(item['snapshot'] as Map);
    }
    return indicators.firstWhere(
      (i) => i['id'] == item['indicatorId'],
      orElse: () => {'name': '指标已不存在', 'project': ''},
    );
  }

  Future<void> chooseIndicators(BuildContext ctx) async {
    final d = editing!;
    final items = maps(d['items']);
    final selected = items.map((i) => '${i['indicatorId']}').toSet();
    final result = await showHrConfigPicker<String>(
      ctx,
      title: '选择考核指标',
      selected: selected,
      options: [
        for (final i in indicators.where(
          (i) => i['enabled'] == true || selected.contains('${i['id']}'),
        ))
          HrConfigOption(
            '${i['id']}',
            '${i['name']}',
            subtitle:
                '${i['project']} · 默认权重 ${i['weight']}% · ${i['instructions'] ?? ''} ${maps(i['bands']).map((b) => b['description']).join(' ')}',
          ),
      ],
    );
    if (result == null || !mounted) return;
    // Filtering and cancellation never replace the selected items' snapshots.
    final next = [
      for (final item in items)
        if (result.contains('${item['indicatorId']}')) item,
    ];
    for (final i in indicators) {
      if (result.contains('${i['id']}') && !selected.contains('${i['id']}')) {
        final item = {
          'indicatorId': i['id'],
          'weight': i['weight'],
          'snapshot': jsonDecode(jsonEncode(i)),
        };
        final dimension = itemDimension(item);
        var insertAt = next.length;
        for (var index = next.length - 1; index >= 0; index--) {
          if (itemDimension(next[index]) == dimension) {
            insertAt = index + 1;
            break;
          }
        }
        next.insert(insertAt, item);
      }
    }
    setState(() => d['items'] = next);
  }

  String itemDimension(Map<String, dynamic> item) {
    final name = '${effective(item)['project'] ?? ''}'.trim();
    return name.isEmpty ? '未分组' : name;
  }

  List<_IndicatorGroup> indicatorGroups(List<Map<String, dynamic>> items) {
    final order = <String>[];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final key = itemDimension(item);
      grouped
          .putIfAbsent(key, () {
            order.add(key);
            return <Map<String, dynamic>>[];
          })
          .add(item);
    }
    return [for (final key in order) _IndicatorGroup(key, grouped[key]!)];
  }

  void applyGroups(List<_IndicatorGroup> groups) {
    editing!['items'] = [
      for (final group in groups)
        for (final item in group.items) item,
    ];
  }

  void moveDimension(int index, int steps) {
    final groups = indicatorGroups(maps(editing!['items']));
    final target = (index + steps).clamp(0, groups.length - 1);
    if (target == index) return;
    final moved = groups.removeAt(index);
    groups.insert(target, moved);
    setState(() => applyGroups(groups));
  }

  void moveIndicator(String dimension, int index, int steps) {
    final groups = indicatorGroups(maps(editing!['items']));
    final group = groups.firstWhere((entry) => entry.name == dimension);
    final target = (index + steps).clamp(0, group.items.length - 1);
    if (target == index) return;
    final items = [...group.items];
    final moved = items.removeAt(index);
    items.insert(target, moved);
    group.items
      ..clear()
      ..addAll(items);
    setState(() => applyGroups(groups));
  }

  Future<void> editItem(BuildContext ctx, Map<String, dynamic> item) async {
    final result = await showHrTemplateItemEditor(
      ctx,
      item,
      direct: editing!['scoreMode'] == 'direct',
    );
    if (result == null || !mounted) return;
    setState(
      () => editing!['items'] = [
        for (final old in maps(editing!['items']))
          if (old['indicatorId'] == item['indicatorId']) result else old,
      ],
    );
  }

  Future<void> chooseScope(BuildContext ctx, {required bool people}) async {
    final d = editing!, field = people ? 'userIds' : 'departmentIds';
    final selected = (d[field] as List)
        .whereType<num>()
        .map((v) => v.toInt())
        .toSet();
    final result = await showHrConfigPicker<int>(
      ctx,
      title: people ? '选择指定人员' : '选择适用部门',
      selected: selected,
      options: people
          ? [
              for (final u in users)
                HrConfigOption(
                  u.userId,
                  u.displayName,
                  subtitle: u.department ?? '',
                  leading: ImUserAvatar(
                    key: ValueKey('hr-picker-avatar-${u.userId}'),
                    initial: u.displayName.trim().isEmpty
                        ? '?'
                        : u.displayName.trim().characters.first,
                    seed: u.userId,
                    size: 40,
                    borderRadius: 10,
                    avatarPreset: u.avatarPreset,
                    avatarObjectKey: u.avatarObjectKey,
                    avatarService: _avatars,
                    fallbackBackground: hrConfigPurple,
                    fallbackForeground: Colors.white,
                  ),
                ),
            ]
          : [
              for (final dep in departments)
                HrConfigOption(
                  dep.id,
                  dep.name,
                  subtitle: '${dep.userCount} 人',
                ),
            ],
    );
    if (result != null && mounted) setState(() => d[field] = result.toList());
  }

  Future<void> save() async {
    final d = editing!, items = maps(editing!['items']);
    final weight = items.fold<double>(
      0,
      (n, i) => n + ((i['weight'] as num?)?.toDouble() ?? 0),
    );
    if ('${d['name']}'.trim().isEmpty ||
        !weight.isFinite ||
        (weight - 100).abs() > .00001) {
      showDunesToast(context, '请填写模板名称，指标权重合计须为 100%');
      return;
    }
    if (d['enabled'] == true &&
        (d['departmentIds'] as List).isEmpty &&
        (d['userIds'] as List).isEmpty &&
        (d['keywords'] as List).isEmpty) {
      showDunesToast(context, '请指定适用部门、人员或岗位关键词');
      return;
    }
    final next = [...templates],
        index = templates.indexWhere((t) => t['id'] == d['id']);
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

  Future<void> preview(BuildContext ctx) => showHrConfigPanel<void>(
    ctx,
    HrConfigPanel(
      title: '考核表预览',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: HrAssessmentSheet(
          lines: [
            for (final item in maps(editing!['items']))
              {
                ...effective(item),
                'weight': item['weight'],
                'directScore': editing!['scoreMode'] == 'direct',
              },
          ],
        ),
      ),
    ),
    maxWidth: 1180,
  );

  Widget field(String label, Widget child) =>
      HrConfigLabel(label, child: child);
  Widget gap() => const SizedBox(height: 16);

  Widget modeField(BuildContext ctx) {
    final direct = editing!['scoreMode'] == 'direct';
    return field(
      '计分方式',
      MenuAnchor(
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          side: WidgetStatePropertyAll(
            BorderSide(color: hrConfigBorder(ctx, const Color(0xFFECE7F3))),
          ),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: .12),
          ),
          backgroundColor: WidgetStatePropertyAll(
            hrConfigSurface(ctx, Colors.white),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        ),
        menuChildren: [
          for (final option in [(true, '按指标分值直接计分'), (false, '百分制加权计分')])
            MenuItemButton(
              onPressed: () => setState(
                () => editing!['scoreMode'] = option.$1 ? 'direct' : '',
              ),
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(230, 42)),
                backgroundColor: WidgetStatePropertyAll(
                  direct == option.$1
                      ? hrConfigSurface(ctx, const Color(0xFFF2ECFC))
                      : Colors.transparent,
                ),
              ),
              trailingIcon: direct == option.$1
                  ? Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: hrConfigColor(ctx, hrConfigPurple),
                    )
                  : null,
              child: Text(option.$2, style: const TextStyle(fontSize: 13)),
            ),
        ],
        builder: (ctx, controller, _) => Material(
          color: hrConfigSurface(ctx, const Color(0xFFF7F6FA)),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: const ValueKey('hr-template-mode'),
            borderRadius: BorderRadius.circular(10),
            onTap: saving
                ? null
                : () {
                    controller.isOpen ? controller.close() : controller.open();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      direct ? '按指标分值直接计分' : '百分制加权计分',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget basicSection(BuildContext ctx) => HrConfigSection(
    title: '基本信息',
    icon: Icons.tune_rounded,
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          editing!['enabled'] == true ? '已启用' : '已停用',
          style: TextStyle(
            fontSize: 12,
            color: hrConfigColor(ctx, const Color(0xFF8C8298)),
          ),
        ),
        Transform.scale(
          scale: .8,
          child: Switch(
            value: editing!['enabled'] == true,
            onChanged: saving
                ? null
                : (v) => setState(() => editing!['enabled'] = v),
          ),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (ctx, box) {
        final name = field(
          '模板名称',
          TextFormField(
            key: const ValueKey('hr-template-name'),
            initialValue: '${editing!['name']}',
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: '例如：财务部月度考核'),
            onChanged: (v) => editing!['name'] = v,
            enabled: !saving,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (box.maxWidth >= 560)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 16),
                  Expanded(child: modeField(ctx)),
                ],
              )
            else ...[
              name,
              gap(),
              modeField(ctx),
            ],
            const SizedBox(height: 12),
            Text(
              editing!['scoreMode'] == 'direct'
                  ? '各项按指标分值打分，总分直接相加。'
                  : '各项按 0–100 分评分，再按指标权重汇总。',
              style: TextStyle(
                fontSize: 12,
                color: hrConfigColor(ctx, const Color(0xFF8C8298)),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget scopeField(BuildContext ctx, {required bool people}) {
    final ids = editing![people ? 'userIds' : 'departmentIds'] as List;
    final names = people
        ? [
            for (final u in users)
              if (ids.contains(u.userId)) u.displayName,
          ]
        : [
            for (final d in departments)
              if (ids.contains(d.id)) d.name,
          ];
    return field(
      people ? '指定人员' : '适用部门',
      Material(
        color: hrConfigSurface(ctx, const Color(0xFFF7F6FA)),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey(
            people ? 'hr-template-users' : 'hr-template-departments',
          ),
          borderRadius: BorderRadius.circular(10),
          onTap: saving ? null : () => chooseScope(ctx, people: people),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(
                  people
                      ? Icons.person_outline_rounded
                      : Icons.account_tree_outlined,
                  size: 18,
                  color: hrConfigColor(ctx, hrConfigPurple),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    names.isEmpty
                        ? (ids.isEmpty ? '请选择' : '已选 ${ids.length} 项')
                        : names.join('、'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: hrConfigColor(
                        ctx,
                        names.isEmpty && ids.isEmpty
                            ? const Color(0xFFA39BAE)
                            : const Color(0xFF302B39),
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget scopeSection(BuildContext ctx) => HrConfigSection(
    title: '适用范围',
    icon: Icons.people_outline_rounded,
    subtitle: '指定人员优先于部门；未指定时按岗位关键词匹配。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        scopeField(ctx, people: false),
        gap(),
        scopeField(ctx, people: true),
        gap(),
        field(
          '岗位关键词',
          TextFormField(
            key: ValueKey('keywords-${editing!['id']}'),
            initialValue: (editing!['keywords'] as List).join('，'),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: '可选，多个词用逗号分隔'),
            enabled: !saving,
            onChanged: (v) => editing!['keywords'] = v
                .split(RegExp('[,，]'))
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList(),
          ),
        ),
        gap(),
        field(
          '匹配优先级',
          TextFormField(
            key: ValueKey('priority-${editing!['id']}'),
            initialValue: '${editing!['priority'] ?? 10}',
            style: const TextStyle(fontSize: 13),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '数字越大越优先'),
            enabled: !saving,
            onChanged: (v) => editing!['priority'] = int.tryParse(v) ?? 10,
          ),
        ),
      ],
    ),
  );

  Widget indicatorSection(BuildContext ctx) {
    final items = maps(editing!['items']);
    final searching = indicatorSearch.text.trim().isNotEmpty;
    final allGroups = indicatorGroups(items);
    final visibleGroups = <_IndicatorGroup>[];
    for (final group in allGroups) {
      final shown = group.items.where((item) {
        final source = effective(item);
        return hrPerformanceMatchesSearch(indicatorSearch.text, [
          '${source['name']}',
          '${source['project']}',
          '${source['instructions'] ?? ''}',
          ...maps(source['bands']).map((band) => '${band['description']}'),
        ]);
      }).toList();
      if (shown.isEmpty) continue;
      visibleGroups.add(
        _IndicatorGroup(
          group.name,
          shown,
          weight: group.weight,
          totalCount: group.items.length,
        ),
      );
    }
    final canReorder = !searching && !saving && visibleGroups.isNotEmpty;
    final buttonStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return HrConfigSection(
      title: '考核内容',
      icon: Icons.assignment_outlined,
      subtitle: '一个考核维度对应多项指标，维度权重等于其中指标权重之和。按住左侧手柄拖到新位置后松手。',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: '预览最终考核表',
            child: OutlinedButton.icon(
              onPressed: () => preview(ctx),
              style: buttonStyle,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('预览考核表', style: TextStyle(fontSize: 12)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: saving ? null : () => chooseIndicators(ctx),
            style: buttonStyle,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('添加指标', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('hr-template-indicator-search'),
            controller: indicatorSearch,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索已选指标、维度或评分说明',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: indicatorSearch.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空指标搜索',
                      onPressed: () => setState(indicatorSearch.clear),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (visibleGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  items.isEmpty ? '还没有指标，点击“添加指标”开始配置' : '没有匹配的已选指标',
                  style: TextStyle(
                    fontSize: 13,
                    color: hrConfigColor(ctx, const Color(0xFF8C8298)),
                  ),
                ),
              ),
            )
          else
            for (var index = 0; index < visibleGroups.length; index++)
              dimensionCard(
                ctx,
                visibleGroups[index],
                index: index,
                canReorder: canReorder && allGroups.length > 1,
                canReorderItems: canReorder,
              ),
          Text(
            '已选 ${items.length} 项指标，${allGroups.length} 个维度',
            style: TextStyle(
              fontSize: 12,
              color: hrConfigColor(ctx, const Color(0xFF8C8298)),
            ),
          ),
        ],
      ),
    );
  }

  Widget dimensionCard(
    BuildContext ctx,
    _IndicatorGroup group, {
    required int index,
    required bool canReorder,
    required bool canReorderItems,
  }) {
    final indicatorList = Column(
      children: [
        for (var itemIndex = 0; itemIndex < group.items.length; itemIndex++)
          indicatorTile(
            ctx,
            group.items[itemIndex],
            onMove: canReorderItems && group.items.length > 1
                ? (steps) => moveIndicator(group.name, itemIndex, steps)
                : null,
          ),
      ],
    );
    return Container(
      key: ValueKey('hr-template-dimension-${group.name}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hrConfigSurface(ctx, const Color(0xFFFCFBFE)),
        border: Border.all(color: hrConfigBorder(ctx, const Color(0xFFE5DDEF))),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            child: Row(
              children: [
                if (canReorder)
                  _OrderDragHandle(
                    handleKey: ValueKey(
                      'hr-template-dimension-drag-${group.name}',
                    ),
                    extentKey: ValueKey('hr-template-dimension-${group.name}'),
                    message: '拖动调整维度顺序',
                    label: group.name,
                    gap: 12,
                    onMove: (steps) => moveDimension(index, steps),
                  )
                else
                  const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hrConfigSurface(ctx, const Color(0xFFF2ECFC)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: hrConfigColor(ctx, hrConfigPurple),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: hrConfigColor(ctx, const Color(0xFF302B39)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        group.totalCount == group.items.length
                            ? '${group.items.length} 个指标'
                            : '显示 ${group.items.length} / ${group.totalCount} 个指标',
                        style: TextStyle(
                          fontSize: 12,
                          color: hrConfigColor(ctx, const Color(0xFF8C8298)),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '维度权重',
                      style: TextStyle(
                        fontSize: 11,
                        color: hrConfigColor(ctx, const Color(0xFF8C8298)),
                      ),
                    ),
                    Text(
                      _templatePercent(group.weight),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: hrConfigColor(ctx, hrConfigPurple),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: indicatorList,
          ),
        ],
      ),
    );
  }

  Widget indicatorTile(
    BuildContext ctx,
    Map<String, dynamic> item, {
    ValueChanged<int>? onMove,
  }) {
    final source = effective(item);
    final items = maps(editing!['items']);
    return Container(
      key: ValueKey('hr-template-item-${item['indicatorId']}'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: hrConfigSurface(ctx, Colors.white),
        border: Border.all(color: hrConfigBorder(ctx, const Color(0xFFECE7F3))),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (onMove != null)
            _OrderDragHandle(
              handleKey: ValueKey(
                'hr-template-item-drag-${item['indicatorId']}',
              ),
              extentKey: ValueKey('hr-template-item-${item['indicatorId']}'),
              message: '拖动调整指标顺序',
              label: '${source['name']}',
              gap: 8,
              onMove: onMove,
            ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: saving ? null : () => editItem(ctx, item),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    onMove == null ? 12 : 4,
                    12,
                    4,
                    12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: hrConfigSurface(ctx, const Color(0xFFF2ECFC)),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.assessment_outlined,
                          size: 18,
                          color: hrConfigColor(ctx, hrConfigPurple),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${source['name']}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: hrConfigColor(
                                  ctx,
                                  const Color(0xFF302B39),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${maps(source['bands']).length} 个评分分档',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: hrConfigColor(
                                  ctx,
                                  const Color(0xFF8C8298),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _templatePercent(
                          (item['weight'] as num?)?.toDouble() ?? 0,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: hrConfigColor(ctx, hrConfigPurple),
                        ),
                      ),
                      IconButton(
                        tooltip: '编辑模板指标',
                        onPressed: saving ? null : () => editItem(ctx, item),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: '移出模板',
                        onPressed: saving
                            ? null
                            : () => setState(
                                () => editing!['items'] = items
                                    .where(
                                      (entry) =>
                                          entry['indicatorId'] !=
                                          item['indicatorId'],
                                    )
                                    .toList(),
                              ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget catalog(BuildContext ctx) {
    final visible = templates
        .where(
          (t) => hrPerformanceMatchesSearch(templateSearch.text, [
            '${t['name']}',
            ...(t['keywords'] as List? ?? []).map((v) => '$v'),
            ...departments
                .where(
                  (d) => (t['departmentIds'] as List? ?? []).contains(d.id),
                )
                .map((d) => d.name),
            ...users
                .where((u) => (t['userIds'] as List? ?? []).contains(u.userId))
                .map((u) => u.displayName),
          ]),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('hr-template-search'),
          controller: templateSearch,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索模板、部门、人员或岗位关键词',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: templateSearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空模板搜索',
                    onPressed: () => setState(templateSearch.clear),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: Text('没有匹配的模板，可新建模板或调整关键词')),
          ),
        LayoutBuilder(
          builder: (ctx, box) {
            final columns = box.maxWidth >= 800 ? 2 : 1;
            final width = (box.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final t in visible)
                  SizedBox(
                    width: width,
                    child: Material(
                      color: hrConfigSurface(ctx, Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => edit(t),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: hrConfigBorder(
                                ctx,
                                const Color(0xFFECE7F3),
                              ),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: hrConfigSurface(
                                        ctx,
                                        const Color(0xFFF2ECFC),
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.description_outlined,
                                      size: 21,
                                      color: hrConfigColor(ctx, hrConfigPurple),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${t['name']}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: hrConfigColor(
                                          ctx,
                                          const Color(0xFF302B39),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    t['enabled'] == true ? '启用' : '停用',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hrConfigColor(
                                        ctx,
                                        t['enabled'] == true
                                            ? const Color(0xFF32836C)
                                            : const Color(0xFF8C8298),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '${maps(t['items']).length} 项指标 · ${t['scoreMode'] == 'direct' ? '直接计分' : '加权计分'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hrConfigColor(
                                    ctx,
                                    const Color(0xFF8C8298),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  for (final d in departments)
                                    if ((t['departmentIds'] as List? ?? [])
                                        .contains(d.id))
                                      d.name,
                                  if ((t['userIds'] as List? ?? []).isNotEmpty)
                                    '${(t['userIds'] as List).length} 位指定人员',
                                  ...(t['keywords'] as List? ?? []).map(
                                    (v) => '$v',
                                  ),
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: hrConfigColor(
                                    ctx,
                                    const Color(0xFF8C8298),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => edit(t),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('编辑模板'),
                                  ),
                                  const Spacer(),
                                  Tooltip(
                                    message: '复制模板',
                                    child: TextButton.icon(
                                      onPressed: () => edit(t, copy: true),
                                      icon: const Icon(
                                        Icons.copy_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('复制'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: hrConfigTheme(context),
    child: Builder(
      builder: (ctx) {
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
        final items = maps(d?['items']),
            total = maps(d?['items']).fold<double>(
              0,
              (n, i) => n + ((i['weight'] as num?)?.toDouble() ?? 0),
            );
        return Material(
          color: hrConfigSurface(ctx, const Color(0xFFF7F4FC)),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(ctx).width < 640 ? 16 : 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: d == null
                                    ? widget.listBackTooltip
                                    : '返回模板列表',
                                onPressed: saving ? null : leave,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d == null ? '考核模板' : '编辑考核模板',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: hrConfigColor(
                                          ctx,
                                          const Color(0xFF302B39),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      d == null
                                          ? '组装考核指标，为不同岗位配置适用量表'
                                          : '设置考核内容、评分标准与适用人员',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: hrConfigColor(
                                          ctx,
                                          const Color(0xFF8C8298),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (d == null)
                                FilledButton.icon(
                                  onPressed: () => edit(null),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('新建模板'),
                                )
                              else
                                Tooltip(
                                  message: '考核表预览',
                                  child: OutlinedButton.icon(
                                    onPressed: () => preview(ctx),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('预览'),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          if (d == null)
                            catalog(ctx)
                          else
                            LayoutBuilder(
                              builder: (ctx, box) {
                                final main = Column(
                                  children: [
                                    basicSection(ctx),
                                    gap(),
                                    indicatorSection(ctx),
                                  ],
                                );
                                if (box.maxWidth >= 980) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: main),
                                      const SizedBox(width: 20),
                                      SizedBox(
                                        width: 300,
                                        child: scopeSection(ctx),
                                      ),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [main, gap(), scopeSection(ctx)],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (d != null)
                Container(
                  decoration: BoxDecoration(
                    color: hrConfigSurface(ctx, Colors.white),
                    border: Border(
                      top: BorderSide(
                        color: hrConfigBorder(ctx, const Color(0xFFECE7F3)),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '指标权重合计：${total.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: hrConfigColor(
                                      ctx,
                                      (total - 100).abs() < .00001
                                          ? hrConfigPurple
                                          : const Color(0xFFB6633B),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${items.length} 项指标 · ${indicatorGroups(items).length} 个维度 · 合计须为 100%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: hrConfigColor(
                                      ctx,
                                      const Color(0xFF8C8298),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: saving ? null : save,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 18),
                            label: Text(saving ? '保存中' : '保存模板'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _IndicatorGroup {
  _IndicatorGroup(this.name, this.items, {double? weight, int? totalCount})
    : weight =
          weight ??
          items.fold<double>(
            0,
            (sum, item) => sum + ((item['weight'] as num?)?.toDouble() ?? 0),
          ),
      totalCount = totalCount ?? items.length;

  final String name;
  final List<Map<String, dynamic>> items;
  final double weight;
  final int totalCount;
}

class _OrderDragHandle extends StatefulWidget {
  const _OrderDragHandle({
    required this.handleKey,
    required this.extentKey,
    required this.message,
    required this.label,
    required this.gap,
    required this.onMove,
  });

  final Key handleKey;
  final Key extentKey;
  final String message;
  final String label;
  final double gap;
  final ValueChanged<int> onMove;

  @override
  State<_OrderDragHandle> createState() => _OrderDragHandleState();
}

class _OrderDragHandleState extends State<_OrderDragHandle> {
  double _dy = 0;
  Offset _point = Offset.zero;
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _EagerVerticalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _EagerVerticalDragGestureRecognizer
            >(_EagerVerticalDragGestureRecognizer.new, (instance) {
              instance.onStart = (details) {
                _dy = 0;
                _point = details.globalPosition;
                _showOverlay();
              };
              instance.onUpdate = (details) {
                _dy += details.delta.dy;
                _point = details.globalPosition;
                _entry?.markNeedsBuild();
              };
              instance.onEnd = (_) {
                _finish();
              };
              instance.onCancel = _finish;
            }),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: widget.message,
          child: Padding(
            key: widget.handleKey,
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.drag_indicator_rounded,
              size: 20,
              color: hrConfigColor(context, hrConfigPurple),
            ),
          ),
        ),
      ),
    );
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (context) {
        final width = MediaQuery.sizeOf(context).width;
        final maxLeft = width - 276;
        final left = (_point.dx + 18).clamp(
          16.0,
          maxLeft < 16 ? 16.0 : maxLeft,
        );
        return Positioned(
          left: left,
          top: _point.dy - 24 < 8 ? 8 : _point.dy - 24,
          width: 260,
          child: IgnorePointer(
            child: Material(
              elevation: 8,
              color: hrConfigSurface(context, Colors.white),
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: hrConfigColor(context, hrConfigPurple),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: hrConfigColor(
                            context,
                            const Color(0xFF302B39),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  double _slotExtent() {
    RenderBox? box;
    context.visitAncestorElements((element) {
      if (element.widget.key == widget.extentKey) {
        final render = element.renderObject;
        if (render is RenderBox && render.hasSize) box = render;
        return false;
      }
      return true;
    });
    final height = box?.size.height ?? 72;
    return (height < 24 ? 72 : height) + widget.gap;
  }

  void _finish() {
    final steps = _dragSteps(_dy, _slotExtent());
    _dy = 0;
    _removeOverlay();
    if (steps != 0 && mounted) widget.onMove(steps);
  }
}

int _dragSteps(double dy, double slot) {
  if (!dy.isFinite || !slot.isFinite || slot <= 0) return 0;
  final raw = dy / slot;
  if (raw.abs() < 0.35) return 0;
  final rounded = raw.round();
  if (rounded == 0) return raw.isNegative ? -1 : 1;
  return rounded;
}

class _EagerVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

String _templatePercent(double value) {
  if (!value.isFinite) return '0%';
  final rounded = (value * 10).round() / 10;
  if ((rounded - rounded.roundToDouble()).abs() < 0.001) {
    return '${rounded.toInt()}%';
  }
  return '${rounded.toStringAsFixed(1)}%';
}
