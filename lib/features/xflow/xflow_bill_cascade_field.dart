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
        if (selected.isEmpty && readonly)
          Text(
            '未关联',
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
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: XflowBillAmountSummary(
              rows: selected,
              remainingKind: _cfg.remainingKind,
              billDirection: _cfg.billDirection,
            ),
          ),
        if (!readonly)
          XfAddRowButton(
            label: '+ 添加账单',
            onTap: () => _openPicker(context, selected),
          ),
      ],
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    List<Map<String, dynamic>> selected,
  ) async {
    final picked = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        final width = size.width < 560 ? size.width - 32 : 520.0;
        final height = (size.height * 0.86).clamp(420.0, 720.0);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          backgroundColor: XfProposalUi.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: _BillCascadeSheet(
              service: service,
              config: _cfg,
              already: selected,
              title: field.label,
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    onChanged(picked);
  }
}

class _BillCascadeSheet extends StatefulWidget {
  const _BillCascadeSheet({
    required this.config,
    required this.already,
    required this.title,
    this.service,
  });

  final XflowService? service;
  final XflowBillCascadeConfig config;
  final List<Map<String, dynamic>> already;
  final String title;

  @override
  State<_BillCascadeSheet> createState() => _BillCascadeSheetState();
}

class _BillCascadeSheetState extends State<_BillCascadeSheet> {
  static const _anyProject = '__any__';

  final TextEditingController _queryCtrl = TextEditingController();
  List<Map<String, dynamic>> _types = const [];
  List<Map<String, dynamic>> _projects = const [];
  List<Map<String, dynamic>> _rows = const [];
  late List<Map<String, dynamic>> _picked;
  String? _typeCode;
  String? _projectName = _anyProject;
  DateTime _periodMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loadingTypes = false;
  bool _loadingProjects = false;
  bool _loadingRows = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _picked = [...widget.already];
    if (widget.service != null) {
      _loadTypes();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    setState(() {
      _loadingTypes = true;
      _error = null;
    });
    try {
      final rows = await widget.service!.fetchAssetBillTypes(
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
      _typeCode = (code == null || code.isEmpty) ? null : code;
      _projectName = _anyProject;
      _projects = const [];
      _rows = const [];
    });
    if (_typeCode == null || widget.service == null) return;
    setState(() => _loadingProjects = true);
    try {
      final rows = await widget.service!.fetchAssetBillProjects(
        billDirection: widget.config.billDirection,
        billTypeCode: _typeCode!,
      );
      if (!mounted) return;
      setState(() {
        _projects = rows;
        _loadingProjects = false;
      });
      if (_typeCode != null) await _search();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProjects = false;
        _error = friendlyErrorText(e);
      });
    }
  }

  ({DateTime start, DateTime end}) get _period =>
      xflowBillMonthBounds(_periodMonth);

  String get _dateStart => xflowBillFormatYmd(_period.start);

  String get _dateEnd => xflowBillFormatYmd(_period.end);

  Future<void> _pickMonth() async {
    final picked = await showDialog<DateTime>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _MonthPickerDialog(initial: _periodMonth),
    );
    if (picked == null) return;
    setState(() {
      _periodMonth = DateTime(picked.year, picked.month);
    });
    await _search();
  }

  Future<void> _search() async {
    final type = _typeCode?.trim() ?? '';
    if (type.isEmpty || widget.service == null) return;
    setState(() {
      _loadingRows = true;
      _error = null;
    });
    try {
      final project = (_projectName == null || _projectName == _anyProject)
          ? ''
          : _projectName!.trim();
      final rows = await widget.service!.fetchAssetBills(
        billDirection: widget.config.billDirection,
        billTypeCode: type,
        dateStart: _dateStart,
        dateEnd: _dateEnd,
        projectName: project,
        query: _queryCtrl.text,
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

  String _projectLabel(Map row) => '${row['projectName'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
              Text(
                '已选 ${_picked.length} 笔',
                style: xfInputTextStyle().copyWith(color: DunesColors.text3),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _filterField(
                label: '账单类型',
                child: _BillInlineSelect(
                  value: _typeCode,
                  hint: _loadingTypes ? '加载类型…' : '请选择',
                  enabled: !_loadingTypes && widget.service != null,
                  items: [
                    for (final t in _types)
                      (
                        value: '${t['billTypeCode'] ?? ''}',
                        label: _typeLabel(t),
                      ),
                  ],
                  onChanged: _onType,
                ),
              ),
              _filterField(
                label: '项目',
                child: _BillInlineSelect(
                  value: _projectName,
                  hint: _loadingProjects ? '加载项目…' : '请选择',
                  enabled: _typeCode != null &&
                      !_loadingProjects &&
                      widget.service != null,
                  items: [
                    (value: _anyProject, label: '不限项目'),
                    for (final p in _projects)
                      if (_projectLabel(p).isNotEmpty)
                        (value: _projectLabel(p), label: _projectLabel(p)),
                  ],
                  onChanged: (v) {
                    setState(() => _projectName = v);
                    _search();
                  },
                ),
              ),
              _filterField(
                label: '账单周期',
                child: _BillInlineMonth(
                  value: _periodMonth,
                  onTap: _pickMonth,
                ),
              ),
              _filterField(
                label: '关键词',
                child: xfFixedHeightControl(
                  child: TextField(
                    controller: _queryCtrl,
                    style: xfInputTextStyle(),
                    decoration: xfInputDecoration(
                      hint: '我方主体、对方主体、周期或账单号',
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: '搜索',
                        onPressed: _search,
                        icon: const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: xfInputTextStyle().copyWith(color: DunesColors.coral),
                  ),
                ),
              if (_loadingRows)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_typeCode == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '请先选类型',
                    style: xfInputTextStyle().copyWith(color: DunesColors.text3),
                  ),
                )
              else if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '没有匹配的账单',
                    style: xfInputTextStyle().copyWith(color: DunesColors.text3),
                  ),
                )
              else
                for (final row in _rows)
                  _ResultBillTile(
                    row: row,
                    remainingKind: widget.config.remainingKind,
                    billDirection: widget.config.billDirection,
                    selected: () {
                      final id = xflowBillId(row);
                      return id != null &&
                          _picked.any((e) => xflowBillHasId(e, id));
                    }(),
                    onTap: () => _toggle(row),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterField({
    required String label,
    required Widget child,
    bool compact = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          XfFieldLabel(label: label, compact: compact),
          child,
        ],
      ),
    );
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  xflowBillLabelOf(row),
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (!readonly && onRemove != null)
                XfRemoveButton(onTap: onRemove!),
            ],
          ),
          if (xflowBillTypeProjectLine(row).isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              xflowBillTypeProjectLine(row),
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          XflowBillAmountGrid(
            row: row,
            remainingKind: remainingKind,
            billDirection: billDirection,
          ),
        ],
      ),
    );
  }
}

class _ResultBillTile extends StatelessWidget {
  const _ResultBillTile({
    required this.row,
    required this.remainingKind,
    required this.billDirection,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> row;
  final String remainingKind;
  final String billDirection;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: selected ? DunesColors.accentSoft : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? DunesColors.accent : DunesColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      xflowBillLabelOf(row),
                      style: DunesTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: selected ? DunesColors.accent : DunesColors.text3,
                  ),
                ],
              ),
              if (xflowBillTypeProjectLine(row).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  xflowBillTypeProjectLine(row),
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              XflowBillAmountGrid(
                row: row,
                remainingKind: remainingKind,
                billDirection: billDirection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillInlineSelect extends StatefulWidget {
  const _BillInlineSelect({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String? value;
  final String hint;
  final List<({String value, String label})> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  State<_BillInlineSelect> createState() => _BillInlineSelectState();
}

class _BillInlineSelectState extends State<_BillInlineSelect> {
  final TextEditingController _controller = TextEditingController();
  bool _expanded = false;

  String get _label {
    final value = widget.value;
    if (value == null || value.isEmpty) return '';
    for (final item in widget.items) {
      if (item.value == value) return item.label;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _controller.text = _label;
  }

  @override
  void didUpdateWidget(covariant _BillInlineSelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _label;
    if (_controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _label.isNotEmpty;
    final showMenu = widget.enabled && _expanded && widget.items.isNotEmpty;
    return TapRegion(
      onTapOutside: (_) {
        if (_expanded) setState(() => _expanded = false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          xfFixedHeightControl(
            child: TextField(
              controller: _controller,
              onTap: !widget.enabled
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              readOnly: true,
              enableInteractiveSelection: false,
              style: xfInputTextStyle(),
              decoration: xfInputDecoration(
                hint: widget.hint,
                readonly: !widget.enabled,
              ).copyWith(
                suffixIconConstraints: const BoxConstraints(minWidth: 72),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasText && widget.enabled)
                      IconButton(
                        tooltip: '清除',
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: DunesColors.text3,
                        ),
                        onPressed: () {
                          widget.onChanged(null);
                          setState(() => _expanded = true);
                        },
                      ),
                    IconButton(
                      tooltip: _expanded ? '收起' : '展开',
                      icon: Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: DunesColors.text3,
                      ),
                      onPressed: !widget.enabled
                          ? null
                          : () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showMenu) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DunesColors.border),
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: widget.items.length.clamp(0, 8),
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: DunesColors.borderSoft),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final selected = item.value == widget.value;
                  return ListTile(
                    dense: true,
                    title: Text(
                      item.label,
                      style: xfInputTextStyle().copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? DunesColors.accentDeep
                            : DunesColors.text,
                      ),
                    ),
                    onTap: () {
                      widget.onChanged(item.value);
                      setState(() => _expanded = false);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BillInlineMonth extends StatelessWidget {
  const _BillInlineMonth({required this.value, required this.onTap});

  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final control = xfFixedHeightControl(
      child: InputDecorator(
        decoration: xfInputDecoration(),
        child: Row(
          children: [
            Expanded(
              child: Text(
                xflowBillFormatYm(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: xfInputTextStyle(),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 14,
              color: DunesColors.text3,
            ),
          ],
        ),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: control,
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
    _month = widget.initial.month;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final minYear = now.year - 5;
    final maxYear = now.year + 1;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一年',
                  onPressed: _year <= minYear
                      ? null
                      : () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一年',
                  onPressed: _year >= maxYear
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
                for (var m = 1; m <= 12; m++)
                  InkWell(
                    onTap: () => Navigator.pop(context, DateTime(_year, m)),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: m == _month && _year == widget.initial.year
                            ? DunesColors.accentSoft
                            : DunesColors.bgSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: m == _month && _year == widget.initial.year
                              ? DunesColors.accent
                              : DunesColors.borderSoft,
                        ),
                      ),
                      child: Text(
                        '$m月',
                        style: DunesTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: m == _month && _year == widget.initial.year
                              ? DunesColors.accentDeep
                              : DunesColors.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
