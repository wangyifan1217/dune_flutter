import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'xflow_bill_cascade.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

class XflowBillCascadeField extends StatelessWidget {
  const XflowBillCascadeField({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.service,
    this.readonly = false,
  });

  final XflowField field;
  final dynamic value;
  final void Function(dynamic value) onChanged;
  final XflowService? service;
  final bool readonly;

  XflowBillCascadeConfig get _cfg =>
      XflowBillCascadeConfig.fromField(field.raw);

  @override
  Widget build(BuildContext context) {
    final selected = xflowBillSelectedList(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected.isEmpty)
          Text(
            readonly ? '未关联' : '选填。先选类型、项目和账期，再搜我方主体、对方主体或周期。',
            style: xfInputTextStyle().copyWith(
              color: DunesColors.text3,
              fontSize: 12,
            ),
          ),
        for (final row in selected)
          _SelectedBillTile(
            row: row,
            remainingKind: _cfg.remainingKind,
            billDirection: _cfg.billDirection,
            readonly: readonly,
            onRemove: readonly
                ? null
                : () {
                    final id = xflowBillId(row);
                    onChanged([
                      for (final item in selected)
                        if (xflowBillId(item) != id) item,
                    ]);
                  },
          ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          XflowBillAmountSummary(
            rows: selected,
            remainingKind: _cfg.remainingKind,
            billDirection: _cfg.billDirection,
          ),
        ],
        if (!readonly) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: service == null
                  ? null
                  : () => _openPicker(context, selected),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加账单'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    List<Map<String, dynamic>> selected,
  ) async {
    final picked = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BillCascadeSheet(
        service: service!,
        config: _cfg,
        already: selected,
        title: field.label,
      ),
    );
    if (picked == null) return;
    onChanged(picked);
  }
}

class _SelectedBillTile extends StatelessWidget {
  const _SelectedBillTile({
    required this.row,
    required this.remainingKind,
    required this.billDirection,
    required this.readonly,
    this.onRemove,
  });

  final Map<String, dynamic> row;
  final String remainingKind;
  final String billDirection;
  final bool readonly;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: XfProposalUi.cardAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: XfProposalUi.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  xflowBillLabelOf(row),
                  style: xfInputTextStyle().copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                XflowBillAmountGrid(
                  row: row,
                  remainingKind: remainingKind,
                  billDirection: billDirection,
                ),
              ],
            ),
          ),
          if (!readonly)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
        ],
      ),
    );
  }
}

class _BillCascadeSheet extends StatefulWidget {
  const _BillCascadeSheet({
    required this.service,
    required this.config,
    required this.already,
    required this.title,
  });

  final XflowService service;
  final XflowBillCascadeConfig config;
  final List<Map<String, dynamic>> already;
  final String title;

  @override
  State<_BillCascadeSheet> createState() => _BillCascadeSheetState();
}

class _BillCascadeSheetState extends State<_BillCascadeSheet> {
  static const _anyProject = '__any__';

  List<Map<String, dynamic>> _types = const [];
  List<Map<String, dynamic>> _projects = const [];
  List<Map<String, dynamic>> _rows = const [];
  String? _typeCode;
  String? _projectName = _anyProject;
  DateTimeRange? _range;
  String _query = '';
  bool _loadingTypes = true;
  bool _loadingProjects = false;
  bool _loadingRows = false;
  String? _error;
  late List<Map<String, dynamic>> _picked;

  @override
  void initState() {
    super.initState();
    _picked = [...widget.already];
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() {
      _loadingTypes = true;
      _error = null;
    });
    try {
      final rows = await widget.service.fetchAssetBillTypes(
        widget.config.billDirection,
      );
      if (!mounted) return;
      setState(() {
        _types = rows;
        _loadingTypes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTypes = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  Future<void> _onType(String? code) async {
    setState(() {
      _typeCode = code;
      _projectName = _anyProject;
      _projects = const [];
      _rows = const [];
    });
    if (code == null || code.isEmpty) return;
    setState(() => _loadingProjects = true);
    try {
      final rows = await widget.service.fetchAssetBillProjects(
        billDirection: widget.config.billDirection,
        billTypeCode: code,
      );
      if (!mounted) return;
      setState(() {
        _projects = rows;
        _loadingProjects = false;
      });
      if (_range != null) await _search();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProjects = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  String get _dateStart => _range == null
      ? ''
      : '${_range!.start.year}-${_range!.start.month.toString().padLeft(2, '0')}-${_range!.start.day.toString().padLeft(2, '0')}';

  String get _dateEnd => _range == null
      ? ''
      : '${_range!.end.year}-${_range!.end.month.toString().padLeft(2, '0')}-${_range!.end.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _search();
  }

  Future<void> _search() async {
    final type = _typeCode?.trim() ?? '';
    if (type.isEmpty || _range == null) return;
    setState(() {
      _loadingRows = true;
      _error = null;
    });
    try {
      final project = (_projectName == null || _projectName == _anyProject)
          ? ''
          : _projectName!.trim();
      final rows = await widget.service.fetchAssetBills(
        billDirection: widget.config.billDirection,
        billTypeCode: type,
        dateStart: _dateStart,
        dateEnd: _dateEnd,
        projectName: project,
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loadingRows = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRows = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  void _toggle(Map<String, dynamic> row) {
    final id = xflowBillId(row);
    if (id == null) return;
    final exists = _picked.any((e) => xflowBillHasId(e, id));
    setState(() {
      if (exists) {
        _picked = [for (final e in _picked) if (!xflowBillHasId(e, id)) e];
      } else {
        _picked = [
          ..._picked,
          xflowBillSnapshot(
            row,
            remainingKind: widget.config.remainingKind,
            billDirection: widget.config.billDirection,
          ),
        ];
      }
    });
  }

  String _typeLabel(Map row) {
    final name = '${row['billTypeName'] ?? ''}'.trim();
    final code = '${row['billTypeCode'] ?? ''}'.trim();
    return name.isNotEmpty ? name : code;
  }

  String _projectLabel(Map row) {
    final name = '${row['projectName'] ?? ''}'.trim();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (context, scroll) {
          return Material(
            color: XfProposalUi.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: XfProposalUi.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: DunesTypography.sans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, _picked),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _dropdown<String>(
                        label: '账单类型',
                        value: _typeCode,
                        hint: _loadingTypes ? '加载类型…' : '请选择类型',
                        items: [
                          for (final t in _types)
                            DropdownMenuItem(
                              value: '${t['billTypeCode'] ?? ''}',
                              child: Text(_typeLabel(t)),
                            ),
                        ],
                        onChanged: _loadingTypes ? null : _onType,
                      ),
                      const SizedBox(height: 10),
                      _dropdown<String>(
                        label: '项目',
                        value: _projectName,
                        hint: _loadingProjects ? '加载项目…' : '请选择项目',
                        items: [
                          const DropdownMenuItem(
                            value: _anyProject,
                            child: Text('不限项目'),
                          ),
                          for (final p in _projects)
                            if (_projectLabel(p).isNotEmpty)
                              DropdownMenuItem(
                                value: _projectLabel(p),
                                child: Text(_projectLabel(p)),
                              ),
                        ],
                        onChanged: _typeCode == null || _loadingProjects
                            ? null
                            : (v) {
                                setState(() => _projectName = v);
                                _search();
                              },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '账期',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _pickRange,
                        borderRadius: BorderRadius.circular(9),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(
                            _range == null
                                ? '请选择账期起止（必选）'
                                : '$_dateStart  ~  $_dateEnd',
                            style: xfInputTextStyle().copyWith(
                              color: _range == null
                                  ? DunesColors.text3
                                  : DunesColors.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '搜索我方主体、对方主体、周期或账单号',
                        ),
                        onChanged: (v) => _query = v,
                        onSubmitted: (_) => _search(),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _typeCode == null || _range == null
                              ? null
                              : _search,
                          child: const Text('搜索'),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            style: xfInputTextStyle().copyWith(
                              color: DunesColors.coral,
                            ),
                          ),
                        ),
                      if (_loadingRows)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_typeCode == null || _range == null)
                        Text(
                          '请先选类型和账期',
                          style: xfInputTextStyle().copyWith(
                            color: DunesColors.text3,
                          ),
                        )
                      else if (_rows.isEmpty)
                        Text(
                          '没有匹配的账单',
                          style: xfInputTextStyle().copyWith(
                            color: DunesColors.text3,
                          ),
                        )
                      else
                        for (final row in _rows)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: () {
                              final id = xflowBillId(row);
                              return id != null &&
                                  _picked.any((e) => xflowBillHasId(e, id));
                            }(),
                            onChanged: (_) => _toggle(row),
                            title: Text(xflowBillLabelOf(row)),
                            subtitle: Text(
                              xflowBillAmountLine(
                                row,
                                widget.config.remainingKind,
                                billDirection: widget.config.billDirection,
                              ),
                            ),
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
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DunesTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          value: items.any((e) => e.value == value) ? value : null,
          hint: Text(hint),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}


class XflowBillAmountGrid extends StatelessWidget {
  const XflowBillAmountGrid({
    super.key,
    required this.row,
    required this.remainingKind,
    this.billDirection = '',
    this.compact = false,
  });

  final Map<String, dynamic> row;
  final String remainingKind;
  final String billDirection;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final labels = xflowBillAmountLabels(
      remainingKind,
      billDirection: billDirection,
    );
    final values = xflowBillAmountValues(row, remainingKind);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labels[i],
                    style: DunesTypography.sans(
                      fontSize: compact ? 10 : 11,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    values[i],
                    style: DunesTypography.sans(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: i == labels.length - 1
                          ? DunesColors.accentDeep
                          : DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class XflowBillAmountSummary extends StatelessWidget {
  const XflowBillAmountSummary({
    super.key,
    required this.rows,
    required this.remainingKind,
    this.billDirection = '',
  });

  final List<Map<String, dynamic>> rows;
  final String remainingKind;
  final String billDirection;

  @override
  Widget build(BuildContext context) {
    final label = xflowBillRemainingSummaryLabel(
      remainingKind,
      billDirection: billDirection,
    );
    final sum = xflowBillMoney(
      xflowBillSelectedRemainingSum(rows, remainingKind),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: DunesColors.accentSoft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
              ),
            ),
          ),
          Text(
            sum,
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DunesColors.accentDeep,
            ),
          ),
        ],
      ),
    );
  }
}
