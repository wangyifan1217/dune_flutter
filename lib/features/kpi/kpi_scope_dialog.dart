import 'package:flutter/material.dart';
import 'workbench_kpi_service.dart';

const _purple = Color(0xFF6741CF);
const _ink = Color(0xFF211B36);
const _muted = Color(0xFF77748B);
const _border = Color(0xFFE6E1F1);
const _lavender = Color(0xFFF0EAFC);

class KpiScopeDialog extends StatefulWidget {
  const KpiScopeDialog({super.key, required this.service});
  final WorkbenchKpiService service;

  @override
  State<KpiScopeDialog> createState() => _KpiScopeDialogState();
}

class _KpiScopeDialogState extends State<KpiScopeDialog> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> catalog = [];
  List<Map<String, dynamic>> lighthouseOptions = [];
  bool loadingOptions = true;
  bool optionsUnavailable = false;
  int? selected;
  Map<String, dynamic>? editing;
  bool loading = true;
  bool mobileEditing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLighthouseOptions();
  }

  Future<void> _loadLighthouseOptions() async {
    try {
      final options = await widget.service.listLighthouseScopeOptions();
      if (mounted)
        setState(() {
          lighthouseOptions = options;
          loadingOptions = false;
          optionsUnavailable = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loadingOptions = false;
          optionsUnavailable = true;
        });
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _load({int? selectUser}) async {
    try {
      final result = await widget.service.listScopeRules();
      var productCatalog = <Map<String, dynamic>>[];
      try {
        productCatalog = await widget.service.listScopeCatalog();
      } catch (_) {
        // Existing task choices remain available when the catalog is unavailable.
      }
      if (!mounted) return;
      setState(() {
        rows = result;
        catalog = productCatalog;
        selected =
            selectUser ??
            selected ??
            (rows.isEmpty ? null : (rows.first['userId'] as num).toInt());
        loading = false;
        error = null;
        if (editing == null && selected != null) {
          final matches = rows.where((row) => row['userId'] == selected);
          if (matches.isNotEmpty) editing = Map.of(matches.first);
        }
      });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  void _selectPerson(int id) {
    final matches = rows.where((row) => row['userId'] == id);
    setState(() {
      selected = id;
      editing = matches.isEmpty ? null : Map.of(matches.first);
    });
  }

  void _add(Map<int, String> people) {
    setState(() {
      editing = {
        'id': 0,
        if (selected != null) 'userId': selected,
        if (selected != null) 'userName': people[selected] ?? '',
        'enabled': true,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final people = <int, String>{};
    for (final row in rows) {
      final id = (row['userId'] as num?)?.toInt();
      if (id != null) people[id] = '${row['userName'] ?? ''}';
    }
    final matches = people.entries
        .where((e) => e.value.contains(search.text.trim()))
        .toList();
    final current = rows.where((row) => row['userId'] == selected).toList();
    if (MediaQuery.sizeOf(context).width < 700) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 700,
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          '绩效任务设置',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (loading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null)
                  Expanded(child: Center(child: Text('加载失败：$error')))
                else if (mobileEditing && editing != null)
                  Expanded(
                    child: _ScopeEdit(
                      key: ValueKey(
                        'mobile-${editing!['id']}-${editing!['userId']}',
                      ),
                      service: widget.service,
                      initial: editing!,
                      rows: rows,
                      catalog: catalog,
                      lighthouseOptions: lighthouseOptions,
                      loadingOptions: loadingOptions,
                      optionsUnavailable: optionsUnavailable,
                      retryOptions: _loadLighthouseOptions,
                      onCancel: () => setState(() => mobileEditing = false),
                      onSaved: (id) async {
                        setState(() {
                          selected = id;
                          editing = null;
                          mobileEditing = false;
                        });
                        await _load(selectUser: id);
                      },
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            decoration: _inputDecoration(
                              '搜索人员姓名',
                              icon: Icons.search,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 55,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final person in matches)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(person.value),
                                    selected: selected == person.key,
                                    onSelected: (_) =>
                                        _selectPerson(person.key),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${people[selected] ?? '请选择人员'} · 共 ${current.length} 项',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  _add(people);
                                  setState(() => mobileEditing = true);
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('新增任务'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: current.length,
                            itemBuilder: (context, index) {
                              final row = current[index];
                              final product =
                                  [row['productName'], row['productL3']]
                                      .where(
                                        (v) =>
                                            v != null && '$v'.trim().isNotEmpty,
                                      )
                                      .join(' / ');
                              return ListTile(
                                title: Text(product.isEmpty ? '全部产品' : product),
                                subtitle: Text(
                                  '${row['province'] == null || '${row['province']}'.isEmpty ? '全国' : row['province']} · ${row['validFrom'] ?? '不限'} — ${row['validTo'] ?? '不限'}\n${row['enabled'] == true ? '生效中' : '已停用'}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => setState(() {
                                  editing = Map.of(row);
                                  mobileEditing = true;
                                }),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: const Color(0xFFFAF9FE),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '绩效任务设置',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '维护人员的绩效考核范围',
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20, color: _muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _purple),
                  ),
                )
              else if (error != null)
                Expanded(child: Center(child: Text('加载失败：$error')))
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final leftWidth = constraints.maxWidth < 950
                          ? 150.0
                          : 195.0;
                      final editorWidth = constraints.maxWidth < 950
                          ? 250.0
                          : 310.0;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _border),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: leftWidth,
                                    child: Column(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: TextField(
                                            controller: search,
                                            onChanged: (_) => setState(() {}),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: _ink,
                                            ),
                                            decoration: _inputDecoration(
                                              '搜索人员姓名',
                                              icon: Icons.search,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: ListView(
                                            children: [
                                              for (final person in matches)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                        vertical: 2,
                                                      ),
                                                  child: Material(
                                                    color:
                                                        person.key == selected
                                                        ? const Color(
                                                            0xFFECE4FC,
                                                          )
                                                        : Colors.transparent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      onTap: () =>
                                                          _selectPerson(
                                                            person.key,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 11,
                                                            ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .person_outline_rounded,
                                                              size: 17,
                                                              color:
                                                                  person.key ==
                                                                      selected
                                                                  ? _purple
                                                                  : _muted,
                                                            ),
                                                            const SizedBox(
                                                              width: 9,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                person.value,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                  color: _ink,
                                                                  fontWeight:
                                                                      person.key ==
                                                                          selected
                                                                      ? FontWeight
                                                                            .w700
                                                                      : FontWeight
                                                                            .w500,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.info_outline,
                                                size: 14,
                                                color: _muted,
                                              ),
                                              SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  '灯塔看数权限单独管理',
                                                  style: TextStyle(
                                                    color: _muted,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1, color: _border),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${people[selected] ?? '请选择人员'} · 绩效任务',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    color: _ink,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '共 ${current.length} 项',
                                                style: const TextStyle(
                                                  color: _muted,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              FilledButton.icon(
                                                onPressed: () => _add(people),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: _purple,
                                                  foregroundColor: Colors.white,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 16,
                                                ),
                                                label: const Text(
                                                  '新增任务',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _lavender,
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                            child: const Row(
                                              children: [
                                                Expanded(
                                                  flex: 4,
                                                  child: Text(
                                                    '产品 / 具体业务',
                                                    style: _tableHeader,
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    '考核范围',
                                                    style: _tableHeader,
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    '有效期',
                                                    style: _tableHeader,
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    '状态',
                                                    style: _tableHeader,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 38,
                                                  child: Text(
                                                    '操作',
                                                    style: _tableHeader,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount: current.length,
                                              itemBuilder: (context, index) {
                                                final row = current[index];
                                                final name =
                                                    [
                                                          row['productName'],
                                                          row['productL3'],
                                                        ]
                                                        .where(
                                                          (v) =>
                                                              v != null &&
                                                              '$v'
                                                                  .trim()
                                                                  .isNotEmpty,
                                                        )
                                                        .join(' / ');
                                                final province =
                                                    '${row['province'] ?? ''}'
                                                        .trim();
                                                final from =
                                                    '${row['validFrom'] ?? ''}'
                                                        .trim();
                                                final to =
                                                    '${row['validTo'] ?? ''}'
                                                        .trim();
                                                final active =
                                                    row['enabled'] == true;
                                                return Container(
                                                  decoration:
                                                      const BoxDecoration(
                                                        border: Border(
                                                          bottom: BorderSide(
                                                            color: _border,
                                                          ),
                                                        ),
                                                      ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        flex: 4,
                                                        child: Text(
                                                          name.isEmpty
                                                              ? '全部产品'
                                                              : name,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: _ink,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 2,
                                                        child: Text(
                                                          province.isEmpty
                                                              ? '全国'
                                                              : province,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color: _ink,
                                                              ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 3,
                                                        child: Text(
                                                          '${from.isEmpty ? '不限' : from} — ${to.isEmpty ? '不限' : to}',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: _ink,
                                                              ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 2,
                                                        child: Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 7,
                                                                  vertical: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: active
                                                                  ? const Color(
                                                                      0xFFE4F6EB,
                                                                    )
                                                                  : const Color(
                                                                      0xFFF0EFF4,
                                                                    ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    20,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              active
                                                                  ? '● 生效中'
                                                                  : '已停用',
                                                              style: TextStyle(
                                                                color: active
                                                                    ? const Color(
                                                                        0xFF16854C,
                                                                      )
                                                                    : _muted,
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: 38,
                                                        child: InkWell(
                                                          onTap: () => setState(
                                                            () => editing =
                                                                Map.of(row),
                                                          ),
                                                          child: const Padding(
                                                            padding:
                                                                EdgeInsets.symmetric(
                                                                  vertical: 10,
                                                                ),
                                                            child: Text(
                                                              '编辑',
                                                              style: TextStyle(
                                                                color: _purple,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: editorWidth,
                            child: editing == null
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: _border),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        '选择任务进行编辑',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                : _ScopeEdit(
                                    key: ValueKey(
                                      '${editing!['id']}-${editing!['userId']}',
                                    ),
                                    service: widget.service,
                                    initial: editing!,
                                    rows: rows,
                                    catalog: catalog,
                                    lighthouseOptions: lighthouseOptions,
                                    loadingOptions: loadingOptions,
                                    optionsUnavailable: optionsUnavailable,
                                    retryOptions: _loadLighthouseOptions,
                                    onCancel: () =>
                                        setState(() => editing = null),
                                    onSaved: (id) async {
                                      setState(() {
                                        selected = id;
                                        editing = null;
                                      });
                                      await _load(selectUser: id);
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _tableHeader = TextStyle(
  color: _ink,
  fontSize: 11,
  fontWeight: FontWeight.w700,
);

InputDecoration _inputDecoration(String hint, {IconData? icon}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _muted, fontSize: 11),
      prefixIcon: icon == null ? null : Icon(icon, size: 16, color: _muted),
      prefixIconConstraints: icon == null
          ? null
          : const BoxConstraints(minWidth: 34),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFCFBFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _purple),
      ),
    );

class _ScopeEdit extends StatefulWidget {
  const _ScopeEdit({
    super.key,
    required this.service,
    required this.initial,
    required this.rows,
    required this.catalog,
    required this.lighthouseOptions,
    required this.loadingOptions,
    required this.optionsUnavailable,
    required this.retryOptions,
    required this.onCancel,
    required this.onSaved,
  });
  final WorkbenchKpiService service;
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> catalog;
  final List<Map<String, dynamic>> lighthouseOptions;
  final bool loadingOptions;
  final bool optionsUnavailable;
  final Future<void> Function() retryOptions;
  final VoidCallback onCancel;
  final Future<void> Function(int userId) onSaved;
  @override
  State<_ScopeEdit> createState() => _ScopeEditState();
}

class _ScopeEditState extends State<_ScopeEdit> {
  final fields = <String, TextEditingController>{};
  int? userId;
  bool enabled = true;
  bool busy = false;
  bool advanced = false;
  List<WorkbenchKpiPersonRef> people = [];
  String? error;

  @override
  void initState() {
    super.initState();
    for (final key in [
      'userName',
      'productGroup',
      'productName',
      'productL3',
      'province',
      'channelGroup',
      'channelName',
      'supplyGroup',
      'validFrom',
      'validTo',
      'note',
    ]) {
      fields[key] = TextEditingController(text: '${widget.initial[key] ?? ''}');
    }
    userId = (widget.initial['userId'] as num?)?.toInt();
    if (const {'全国', '全部', '*'}.contains(fields['province']!.text.trim())) {
      fields['province']!.clear();
    }
    enabled = widget.initial['enabled'] != false;
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (userId == null) {
      setState(() => error = '请选择人员');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selectedUser = userId!;
      await widget.service.saveScopeRule({
        'id': widget.initial['id'] ?? 0,
        'userId': selectedUser,
        'enabled': enabled,
        for (final entry in fields.entries)
          if (entry.key != 'userName') entry.key: entry.value.text.trim(),
      });
      if (!mounted) return;
      await widget.onSaved(selectedUser);
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = '保存失败：$e';
        });
    }
  }

  Future<void> _pickDate(String key) async {
    final initial = DateTime.tryParse(fields[key]!.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null)
      fields[key]!.text =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _field(
    String key,
    String label, {
    String hint = '',
    IconData? icon,
    bool date = false,
  }) {
    final selectable = <String>{
      'productGroup',
      'productName',
      'productL3',
      'province',
      'channelGroup',
      'channelName',
      'supplyGroup',
    }.contains(key);
    final current = fields[key]!.text.trim();
    final product = fields['productName']!.text.trim();
    final channelGroup = fields['channelGroup']!.text.trim();
    final options = <String>{
      if (current.isNotEmpty) current,
      for (final option in widget.lighthouseOptions)
        if ((key != 'productL3' ||
                '${option['productName'] ?? ''}'.trim() == product) &&
            (key != 'productGroup' ||
                product.isEmpty ||
                '${option['productName'] ?? ''}'.trim() == product) &&
            (key != 'channelName' ||
                channelGroup.isEmpty ||
                '${option['channelGroup'] ?? ''}'.trim() == channelGroup) &&
            '${option[key] ?? ''}'.trim().isNotEmpty)
          '${option[key]}'.trim(),
      if (key == 'productName')
        for (final alias in widget.catalog)
          if ('${alias['lighthouseL2'] ?? ''}'.trim().isNotEmpty)
            '${alias['lighthouseL2']}'.trim(),
      if (key == 'productL3')
        for (final alias in widget.catalog)
          if ('${alias['lighthouseL2'] ?? ''}'.trim() == product ||
              '${alias['taskName'] ?? ''}'.trim() == product)
            for (final value in '${alias['lighthouseL3'] ?? ''}'.split(
              RegExp('[、，,]'),
            ))
              if (value.trim().isNotEmpty) value.trim(),
      for (final row in widget.rows)
        if ((key != 'productL3' ||
                '${row['productName'] ?? ''}'.trim() == product) &&
            (key != 'productGroup' ||
                product.isEmpty ||
                '${row['productName'] ?? ''}'.trim() == product) &&
            (key != 'channelName' ||
                channelGroup.isEmpty ||
                '${row['channelGroup'] ?? ''}'.trim() == channelGroup) &&
            '${row[key] ?? ''}'.trim().isNotEmpty)
          '${row[key]}'.trim(),
    }.toList()..sort();
    if (key == 'province') {
      options.removeWhere((value) => const {'全国', '全部', '*'}.contains(value));
    }
    void select(String value) {
      setState(() {
        if (key == 'productName' && current != value) {
          fields['productL3']!.clear();
          final groups = <String>{
            for (final option in [...widget.lighthouseOptions, ...widget.rows])
              if ('${option['productName'] ?? ''}'.trim() == value &&
                  '${option['productGroup'] ?? ''}'.trim().isNotEmpty)
                '${option['productGroup']}'.trim(),
            for (final alias in widget.catalog)
              if ('${alias['lighthouseL2'] ?? ''}'.trim() == value &&
                  '${alias['lighthouseL1'] ?? ''}'.trim().isNotEmpty)
                '${alias['lighthouseL1']}'.trim(),
          };
          fields['productGroup']!.text = groups.length == 1
              ? groups.single
              : '';
        }
        if (key == 'channelGroup' && current != value)
          fields['channelName']!.clear();
        fields[key]!.text = value;
      });
    }

    final input = selectable
        ? DropdownButtonFormField<String>(
            key: ValueKey('$key:$current:${options.join('|')}'),
            initialValue: current,
            isExpanded: true,
            menuMaxHeight: 320,
            decoration: _inputDecoration(hint, icon: icon),
            style: const TextStyle(color: _ink, fontSize: 12),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(
                  key == 'productName'
                      ? '请选择产品'
                      : key == 'province'
                      ? '全国'
                      : key == 'productL3'
                      ? '产品默认范围'
                      : '全部 / 不限制',
                ),
              ),
              for (final value in options)
                DropdownMenuItem(
                  value: value,
                  child: Text(value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => select(value ?? ''),
          )
        : TextField(
            controller: fields[key],
            style: const TextStyle(color: _ink, fontSize: 12),
            decoration: _inputDecoration(hint, icon: icon).copyWith(
              suffixIcon: date
                  ? IconButton(
                      onPressed: () => _pickDate(key),
                      icon: const Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: _muted,
                      ),
                      visualDensity: VisualDensity.compact,
                    )
                  : null,
            ),
            onTap: date ? () => _pickDate(key) : null,
            readOnly: date,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          ),
          Expanded(child: input),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = (widget.initial['id'] as num?)?.toInt() == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isNew ? '新增绩效任务' : '编辑绩效任务',
            style: const TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 70,
                        child: Text(
                          '人员 *',
                          style: TextStyle(color: _ink, fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: fields['userName'],
                          style: const TextStyle(color: _ink, fontSize: 12),
                          decoration: _inputDecoration(
                            '搜索人员',
                            icon: Icons.person_outline,
                          ),
                          onChanged: (q) async {
                            userId = null;
                            try {
                              final result = await widget.service.searchPeople(
                                q,
                              );
                              if (mounted && fields['userName']!.text == q)
                                setState(() => people = result);
                            } catch (e) {
                              if (mounted) setState(() => error = '人员搜索失败：$e');
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  for (final person in people.take(5))
                    ListTile(
                      dense: true,
                      title: Text(
                        person.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => setState(() {
                        userId = person.userId;
                        fields['userName']!.text = person.displayName;
                        people = [];
                      }),
                    ),
                  const SizedBox(height: 10),
                  _field(
                    'productName',
                    '产品 *',
                    hint: '产品名称',
                    icon: Icons.layers_outlined,
                  ),
                  _field(
                    'productL3',
                    '具体业务',
                    hint: '如出行会员、加油会员',
                    icon: Icons.label_outline,
                  ),
                  if (widget.loadingOptions)
                    const Padding(
                      padding: EdgeInsets.only(left: 70, bottom: 8),
                      child: Text(
                        '正在读取灯塔分类…',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    )
                  else if (widget.optionsUnavailable)
                    Padding(
                      padding: const EdgeInsets.only(left: 70, bottom: 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '灯塔分类未连接，当前显示已有任务和映射',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.retryOptions,
                            child: const Text(
                              '重试',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(left: 70, bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '按所选产品选择具体业务；留空按产品默认范围计算',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ),
                  ),
                  _field(
                    'province',
                    '省份',
                    hint: '留空为全国',
                    icon: Icons.location_on_outlined,
                  ),
                  _field('validFrom', '开始日期', hint: '选择日期', date: true),
                  _field('validTo', '结束日期', hint: '选择日期', date: true),
                  Row(
                    children: [
                      const SizedBox(
                        width: 70,
                        child: Text(
                          '生效状态',
                          style: TextStyle(color: _ink, fontSize: 11),
                        ),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          initialValue: enabled,
                          isExpanded: true,
                          decoration: _inputDecoration(''),
                          style: const TextStyle(color: _ink, fontSize: 12),
                          items: const [
                            DropdownMenuItem(value: true, child: Text('生效中')),
                            DropdownMenuItem(value: false, child: Text('已停用')),
                          ],
                          onChanged: (value) =>
                              setState(() => enabled = value ?? true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => advanced = !advanced),
                      icon: Icon(
                        advanced ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                      ),
                      label: const Text('更多范围', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  if (advanced) ...[
                    _field('productGroup', '产品分组'),
                    _field('channelGroup', '渠道分组'),
                    _field('channelName', '渠道'),
                    _field('supplyGroup', '供给'),
                    _field('note', '备注'),
                  ],
                  if (error != null)
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('修改从本月生效', style: TextStyle(color: _muted, fontSize: 10)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: busy ? null : widget.onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _border),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('取消', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('保存修改', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
