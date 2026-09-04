import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'payroll_report_service.dart';

const _payrollAccent = Color(0xFF3D7A8C);
const _identityTokens = [
  '姓名',
  '人员',
  '员工',
  '工号',
  '电话',
  '手机',
  '部门',
  '中心',
  '组织',
  '团队',
  '岗位',
  '职级',
  '身份证',
  '证件',
  '银行',
  '账号',
  '卡号',
  '账户',
  '邮箱',
  '地址',
  '序号',
  '日期',
  '入职',
  '离职',
];
const _costTokens = [
  '人工成本',
  '人力成本',
  '总成本',
  '成本项',
  '成本',
  '工资',
  '薪资',
  '薪酬',
  '实发',
  '应发',
  '社保',
  '公积金',
  '奖金',
  '补贴',
  '津贴',
];

class _PayrollPersonCost {
  const _PayrollPersonCost({
    required this.name,
    required this.department,
    required this.primaryLabel,
    required this.primaryAmount,
    required this.context,
    required this.costItems,
  });

  final String name;
  final String department;
  final String primaryLabel;
  final num? primaryAmount;
  final List<String> context;
  final List<({String label, String value})> costItems;

  String get departmentLabel => department.isEmpty ? '未分配部门' : department;
}

bool _matchesAny(String value, List<String> tokens) =>
    tokens.any((token) => value.contains(token));

bool _isSummaryLabel(String value) {
  final text = value.trim().toLowerCase().replaceAll(
    RegExp(r'[\s\[\]【】()（）<>《》·.\-_/\\:：]+'),
    '',
  );
  if (text.isEmpty) return false;
  const tokens = ['合计', '总计', '小计', '汇总', 'total', 'sum', 'grandtotal'];
  return tokens.any((token) => text == token || text.contains(token));
}

bool _isSummaryRow(PayrollReportTable table, Map<String, dynamic> row) {
  final nameColumn = _firstOrNull(
    table.columns.where(
      (column) => _matchesAny(column.name, ['姓名', '人员', '员工']),
    ),
  );
  final keys = <String>[
    if (nameColumn != null) nameColumn.key,
    if (table.columns.isNotEmpty) table.columns.first.key,
  ];
  return keys.any((key) => _isSummaryLabel('${row[key] ?? ''}'));
}

List<_PayrollPersonCost> _visiblePeople(PayrollReportTable table) {
  return [
    for (var index = 0; index < table.rows.length; index++)
      if (!_isSummaryRow(table, table.rows[index]))
        _toPersonCost(table, table.rows[index], index),
  ].where((person) => !_isSummaryLabel(person.name)).toList(growable: false);
}

void _sortPeople(List<_PayrollPersonCost> people, {required bool descending}) {
  people.sort((a, b) {
    final cmp = (b.primaryAmount ?? 0).compareTo(a.primaryAmount ?? 0);
    if (cmp != 0) return descending ? cmp : -cmp;
    return a.name.compareTo(b.name);
  });
}

T? _firstOrNull<T>(Iterable<T> values) => values.isEmpty ? null : values.first;

bool _looksLikeIdentifier(String raw) =>
    RegExp(r'^\d{11,}$').hasMatch(raw.replaceAll(RegExp(r'[Xx]$'), ''));

num? _asAmount(dynamic value) {
  if (value is num) {
    if (value.abs() >= 10000000000) return null;
    return value;
  }
  final raw = '${value ?? ''}'
      .replaceAll(',', '')
      .replaceAll('¥', '')
      .replaceAll('￥', '')
      .trim();
  if (raw.isEmpty || _looksLikeIdentifier(raw)) return null;
  return num.tryParse(raw);
}

bool _isCostColumn(String name) =>
    _matchesAny(name, _costTokens) && !_matchesAny(name, _identityTokens);

int _primaryRank(String name, num? amount) {
  if (name.contains('人工成本') || name.contains('人力成本')) return 0;
  if (name.contains('总成本')) return 1;
  if (name.contains('实发')) return 2;
  if (name.contains('应发')) return 3;
  if (name.contains('成本项合计') || name.contains('成本合计')) {
    return amount == null || amount == 0 ? 80 : 4;
  }
  if (name.contains('工资') || name.contains('薪资') || name.contains('薪酬')) {
    return 5;
  }
  if (name.contains('成本')) return 6;
  return 10;
}

String _formatAmount(num? amount) {
  if (amount == null) return '—';
  final text = amount.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts.first;
  final negative = whole.startsWith('-');
  final digits = negative ? whole.substring(1) : whole;
  final grouped = digits.replaceAllMapped(
    RegExp(r'(?<!^)(?=(\d{3})+$)'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}¥$grouped.${parts.last}';
}

_PayrollPersonCost _toPersonCost(
  PayrollReportTable table,
  Map<String, dynamic> row,
  int index,
) {
  final columns = table.columns;
  final nameColumn = _firstOrNull(
    columns.where((column) => _matchesAny(column.name, ['姓名', '人员', '员工'])),
  );
  final name = '${nameColumn == null ? '' : row[nameColumn.key] ?? ''}'.trim();
  final costColumns = columns
      .where((column) => _isCostColumn(column.name))
      .toList(growable: false);
  PayrollReportColumn? primaryColumn;
  if (costColumns.isNotEmpty) {
    final ranked = [...costColumns]
      ..sort((a, b) {
        final rankA = _primaryRank(a.name, _asAmount(row[a.key]));
        final rankB = _primaryRank(b.name, _asAmount(row[b.key]));
        return rankA.compareTo(rankB);
      });
    primaryColumn = ranked.first;
  }
  final deptColumn = _firstOrNull(
    columns.where((column) => column.name.contains('部门')),
  );
  final department = '${deptColumn == null ? '' : row[deptColumn.key] ?? ''}'
      .trim();
  final context = columns
      .where(
        (column) => _matchesAny(column.name, ['部门', '中心', '组织', '团队', '岗位']),
      )
      .map((column) => '${row[column.key] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .take(2)
      .toList(growable: false);
  return _PayrollPersonCost(
    name: name.isEmpty ? '员工 ${index + 1}' : name,
    department: department,
    primaryLabel: primaryColumn?.name ?? '人工成本',
    primaryAmount: primaryColumn == null
        ? null
        : _asAmount(row[primaryColumn.key]),
    context: context,
    costItems: costColumns
        .where((column) => column != primaryColumn)
        .map((column) {
          final amount = _asAmount(row[column.key]);
          return (
            label: column.name,
            value: _formatAmount(amount),
            amount: amount,
          );
        })
        .where((item) => item.amount != null && item.amount != 0)
        .take(3)
        .map((item) => (label: item.label, value: item.value))
        .toList(growable: false),
  );
}

class NativePayrollReportPage extends StatefulWidget {
  const NativePayrollReportPage({
    super.key,
    required this.session,
    this.service,
    this.saveExport,
    this.now,
  });
  final AuthSession session;
  final PayrollReportService? service;
  final Future<void> Function(Uint8List bytes, String name)? saveExport;
  final DateTime? now;

  @override
  State<NativePayrollReportPage> createState() =>
      _NativePayrollReportPageState();
}

class _NativePayrollReportPageState extends State<NativePayrollReportPage> {
  late final PayrollReportService _service;
  final _keyword = TextEditingController();
  Timer? _debounce;
  late DateTime _month;
  bool _loadingSheets = true;
  bool _loadingRows = false;
  bool _busy = false;
  String? _error;
  List<PayrollReportSheet> _sheets = const [];
  PayrollReportSheet? _selected;
  PayrollReportTable? _table;
  bool _listView = false;
  bool _groupByDept = false;
  bool _sortDesc = true;

  String get _yearmo =>
      '${_month.year.toString().padLeft(4, '0')}${_month.month.toString().padLeft(2, '0')}';
  String get _monthLabel => '${_month.year}年${_month.month}月';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PayrollReportService(session: widget.session);
    final now = widget.now ?? DateTime.now();
    _month = DateTime(now.year, now.month - 1);
    _keyword.addListener(_onKeywordChanged);
    unawaited(_loadSheets());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _keyword.dispose();
    super.dispose();
  }

  void _onKeywordChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (_selected != null) unawaited(_loadRows());
    });
  }

  Future<void> _loadSheets() async {
    setState(() {
      _loadingSheets = true;
      _error = null;
      _table = null;
    });
    try {
      final sheets = await _service.listSheets(_yearmo);
      if (!mounted) return;
      PayrollReportSheet? preferred;
      for (final sheet in sheets) {
        if (sheet.name.contains('工资报表')) {
          preferred = sheet;
          break;
        }
      }
      setState(() {
        _sheets = sheets;
        _selected = preferred ?? (sheets.isEmpty ? null : sheets.first);
        _loadingSheets = false;
      });
      if (_selected != null) await _loadRows();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error, fallback: '加载工资报表失败');
        _loadingSheets = false;
      });
    }
  }

  Future<void> _loadRows() async {
    final sheet = _selected;
    if (sheet == null) return;
    setState(() {
      _loadingRows = true;
      _error = null;
    });
    try {
      final table = await _service.fetchRows(
        yearmo: _yearmo,
        sheet: sheet,
        q: _keyword.text,
      );
      if (!mounted || sheet != _selected) return;
      setState(() {
        _table = table;
        _loadingRows = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(error, fallback: '加载工资明细失败');
        _loadingRows = false;
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = widget.now ?? DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _PayrollMonthPickerDialog(
        initial: _month,
        firstMonth: DateTime(now.year - 5, 1),
        lastMonth: DateTime(now.year, now.month),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
    await _loadSheets();
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('payroll-confirm-ok'),
            style: FilledButton.styleFrom(backgroundColor: _payrollAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _sync() async {
    final confirmed = await _confirm(
      title: '确认同步工资报表？',
      content: '将同步$_monthLabel的最新工资报表数据。',
      confirmLabel: '确认同步',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.sync(_yearmo);
      if (!mounted) return;
      showDunesToast(context, '$_monthLabel 工资报表已同步');
      await _loadSheets();
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(error, fallback: '同步失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final sheet = _selected;
    if (sheet == null) return;
    final confirmed = await _confirm(
      title: '确认导出工资报表？',
      content: '将导出$_monthLabel「${sheet.name}」的当前查询结果（Excel）。',
      confirmLabel: '确认导出',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await _service.export(
        yearmo: _yearmo,
        sheet: sheet,
        q: _keyword.text,
      );
      final name = '工资报表-$_yearmo-${sheet.name}.xlsx';
      if (widget.saveExport != null) {
        await widget.saveExport!(bytes, name);
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'Excel', extensions: ['xlsx']),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          bytes,
          name: name,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ).saveTo(location.path);
      }
      if (mounted) showDunesToast(context, '已导出 ${sheet.name}');
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(error, fallback: '导出失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F8FA),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      key: const Key('payroll-month'),
                      onPressed: _busy ? null : _pickMonth,
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(_monthLabel),
                    ),
                    FilledButton.icon(
                      key: const Key('payroll-sync'),
                      onPressed: _busy ? null : () => unawaited(_sync()),
                      style: FilledButton.styleFrom(
                        backgroundColor: _payrollAccent,
                      ),
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('同步'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('payroll-export'),
                      onPressed: _busy || _selected == null
                          ? null
                          : () => unawaited(_export()),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('导出'),
                    ),
                    FilterChip(
                      key: const Key('payroll-group-dept'),
                      label: const Text('按部门'),
                      selected: _groupByDept,
                      visualDensity: VisualDensity.compact,
                      selectedColor: _payrollAccent.withValues(alpha: 0.16),
                      checkmarkColor: _payrollAccent,
                      onSelected: (value) =>
                          setState(() => _groupByDept = value),
                    ),
                    FilterChip(
                      key: const Key('payroll-view-list'),
                      label: const Text('列表'),
                      selected: _listView,
                      visualDensity: VisualDensity.compact,
                      selectedColor: _payrollAccent.withValues(alpha: 0.16),
                      checkmarkColor: _payrollAccent,
                      onSelected: (value) => setState(() => _listView = value),
                    ),
                    ActionChip(
                      key: const Key('payroll-sort'),
                      avatar: Icon(
                        _sortDesc
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        size: 16,
                        color: _payrollAccent,
                      ),
                      label: Text(_sortDesc ? '成本高→低' : '成本低→高'),
                      onPressed: () => setState(() => _sortDesc = !_sortDesc),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _keyword,
                  decoration: InputDecoration(
                    hintText: '搜索人员或成本项目',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE8EAED)),
                    ),
                  ),
                ),
                if (_sheets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final sheet in _sheets)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(sheet.name),
                              selected: sheet == _selected,
                              selectedColor: _payrollAccent.withValues(
                                alpha: 0.16,
                              ),
                              onSelected: _busy
                                  ? null
                                  : (_) {
                                      setState(() => _selected = sheet);
                                      unawaited(_loadRows());
                                    },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingSheets || _loadingRows) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text2)),
            TextButton(
              onPressed: () => unawaited(_loadSheets()),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_sheets.isEmpty) {
      return const Center(
        child: Text('该月暂无工资报表', style: TextStyle(color: DunesColors.text3)),
      );
    }
    final table = _table;
    if (table == null || table.rows.isEmpty) {
      return const Center(
        child: Text('暂无匹配的工资明细', style: TextStyle(color: DunesColors.text3)),
      );
    }
    final people = _visiblePeople(table).toList();
    _sortPeople(people, descending: _sortDesc);
    final total = people.fold<num>(
      0,
      (sum, person) => sum + (person.primaryAmount ?? 0),
    );
    final groups = _groupByDept
        ? _departmentGroups(people)
        : <({String title, List<_PayrollPersonCost> people})>[
            (title: '', people: people),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: _costSummary(
                  count: people.length,
                  total: total,
                  label: people.isEmpty ? '人工成本' : people.first.primaryLabel,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, inner) {
                    const gap = 12.0;
                    final cols = _listView
                        ? 1
                        : wide
                        ? (inner.maxWidth >= 900 ? 3 : 2)
                        : 1;
                    final cardWidth =
                        (inner.maxWidth - gap * (cols - 1)) / cols;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final group in groups) ...[
                          if (group.title.isNotEmpty)
                            _departmentHeader(group.people),
                          if (_listView)
                            Column(
                              children: [
                                for (final person in group.people)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _personCostRow(person),
                                  ),
                              ],
                            )
                          else
                            Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final person in group.people)
                                  SizedBox(
                                    width: cardWidth,
                                    child: _personCostCard(person),
                                  ),
                              ],
                            ),
                          if (group.title.isNotEmpty)
                            const SizedBox(height: 16),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<({String title, List<_PayrollPersonCost> people})> _departmentGroups(
    List<_PayrollPersonCost> people,
  ) {
    final map = <String, List<_PayrollPersonCost>>{};
    for (final person in people) {
      map.putIfAbsent(person.departmentLabel, () => []).add(person);
    }
    final groups = [
      for (final entry in map.entries) (title: entry.key, people: entry.value),
    ];
    groups.sort((a, b) {
      final totalA = a.people.fold<num>(
        0,
        (sum, person) => sum + (person.primaryAmount ?? 0),
      );
      final totalB = b.people.fold<num>(
        0,
        (sum, person) => sum + (person.primaryAmount ?? 0),
      );
      final cmp = totalB.compareTo(totalA);
      if (cmp != 0) return _sortDesc ? cmp : -cmp;
      return a.title.compareTo(b.title);
    });
    return groups;
  }

  Widget _departmentHeader(List<_PayrollPersonCost> people) {
    final total = people.fold<num>(
      0,
      (sum, person) => sum + (person.primaryAmount ?? 0),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              people.first.departmentLabel,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${people.length} 人 · ${_formatAmount(total)}',
            style: const TextStyle(color: DunesColors.text2, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _personCostRow(_PayrollPersonCost person) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5ECEE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (person.departmentLabel.isNotEmpty)
                  Text(
                    person.departmentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DunesColors.text3,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatAmount(person.primaryAmount),
                style: const TextStyle(
                  color: _payrollAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                person.primaryLabel,
                style: const TextStyle(color: DunesColors.text3, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _costSummary({
    required int count,
    required num total,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _payrollAccent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_2_outlined, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月人力成本',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.76),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatAmount(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count 人 · $label',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _personCostCard(_PayrollPersonCost person) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5ECEE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D20343A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _payrollAccent.withValues(alpha: 0.12),
                foregroundColor: _payrollAccent,
                child: Text(
                  person.name.substring(0, 1),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (person.context.isNotEmpty)
                      Text(
                        person.context.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DunesColors.text3,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            person.primaryLabel,
            style: const TextStyle(color: DunesColors.text3, fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            _formatAmount(person.primaryAmount),
            style: const TextStyle(
              color: _payrollAccent,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (person.costItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFEAF0F1)),
            const SizedBox(height: 10),
            for (final item in person.costItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${item.label} ${item.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DunesColors.text2,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _PayrollMonthPickerDialog extends StatefulWidget {
  const _PayrollMonthPickerDialog({
    required this.initial,
    required this.firstMonth,
    required this.lastMonth,
  });

  final DateTime initial;
  final DateTime firstMonth;
  final DateTime lastMonth;

  @override
  State<_PayrollMonthPickerDialog> createState() =>
      _PayrollMonthPickerDialogState();
}

class _PayrollMonthPickerDialogState extends State<_PayrollMonthPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(
      widget.firstMonth.year,
      widget.lastMonth.year,
    );
  }

  bool _canSelect(int year, int month) {
    final value = year * 100 + month;
    return value >= widget.firstMonth.year * 100 + widget.firstMonth.month &&
        value <= widget.lastMonth.year * 100 + widget.lastMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择工资月份'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: _year <= widget.firstMonth.year
                      ? null
                      : () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '$_year年',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: _year >= widget.lastMonth.year
                      ? null
                      : () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                for (var month = 1; month <= 12; month++) _monthCell(month),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _monthCell(int month) {
    final enabled = _canSelect(_year, month);
    final selected =
        _year == widget.initial.year && month == widget.initial.month;
    return InkWell(
      onTap: enabled
          ? () => Navigator.pop(context, DateTime(_year, month))
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _payrollAccent
              : enabled
              ? _payrollAccent.withValues(alpha: 0.08)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$month月',
          style: TextStyle(
            color: selected
                ? Colors.white
                : enabled
                ? DunesColors.text
                : DunesColors.text3,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
