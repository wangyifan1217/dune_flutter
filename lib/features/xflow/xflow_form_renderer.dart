import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_upload_field.dart';

typedef XflowFieldChanged = void Function(String key, dynamic value);
typedef XflowFormAction = Future<void> Function(String actionKind);

class XflowFormRenderer extends StatefulWidget {
  const XflowFormRenderer({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    required this.layout,
    this.service,
    this.onAction,
    this.embedded = true,
  });

  final List<XflowField> fields;
  final Map<String, dynamic> values;
  final XflowFieldChanged onChanged;
  final Map<String, dynamic> layout;
  final XflowService? service;
  final XflowFormAction? onAction;
  final bool embedded;

  @override
  State<XflowFormRenderer> createState() => _XflowFormRendererState();
}

class _XflowFormRendererState extends State<XflowFormRenderer> {
  @override
  Widget build(BuildContext context) {
    final hiddenKeys = <String>{};
    final actionKeys = <String>{};
    for (final field in widget.fields) {
      if (field.type == 'row') hiddenKeys.addAll(field.children);
      if (field.type == 'action' &&
          field.raw['actionKind'] != 'excel-import' &&
          field.raw['actionKind'] != 'ai-policy' &&
          field.raw['actionKind'] != 'ai-summary') {
        actionKeys.add(field.key);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _progressCard(),
        _actionBar(actionKeys),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DunesColors.borderSoft),
          ),
          child: Column(
            children: [
              for (final field in widget.fields)
                if (!hiddenKeys.contains(field.key) &&
                    !actionKeys.contains(field.key) &&
                    _isVisible(field))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _fieldWidget(field),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isVisible(XflowField field) {
    final cond = (field.raw['visibleWhen'] ?? '').toString().trim();
    if (cond.isEmpty) return true;
    return _parseCond(cond, widget.values);
  }

  bool _parseCond(String expr, Map<String, dynamic> values) {
    final parts = expr.split('=');
    if (parts.length < 2) return true;
    final key = parts.first.trim();
    final want = parts.sublist(1).join('=').trim();
    final got = values[key];
    if (got is List) return got.contains(want) || got.join('、') == want;
    return (got?.toString() ?? '') == want;
  }

  ({int pct, int bizDone, int bizTotal, int finDone, int finTotal}) _progress() {
    final prog = widget.layout['progress'];
    final biz = _keyList(prog is Map ? prog['biz'] : null);
    final fin = _keyList(prog is Map ? prog['fin'] : null);
    var bizDone = 0;
    var finDone = 0;
    for (final k in biz) {
      if (_hasValue(widget.values[k])) bizDone++;
    }
    for (final k in fin) {
      if (_hasValue(widget.values[k])) finDone++;
    }
    final total = biz.length + fin.length;
    final done = bizDone + finDone;
    final pct = total == 0 ? 0 : ((done / total) * 100).round();
    return (pct: pct, bizDone: bizDone, bizTotal: biz.length, finDone: finDone, finTotal: fin.length);
  }

  List<String> _keyList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  Widget _progressCard() {
    final p = _progress();
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('提案完整度', style: DunesTypography.sans(fontSize: 11)),
              const Spacer(),
              Text('${p.pct}%', style: DunesTypography.sans(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p.pct / 100,
              minHeight: 4,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              color: DunesColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '业务 ${p.bizDone} / ${p.bizTotal}',
                  style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3),
                ),
              ),
              Expanded(
                child: Text(
                  '财务 ${p.finDone} / ${p.finTotal}',
                  style: DunesTypography.sans(fontSize: 10, color: DunesColors.text3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBar(Set<String> actionKeys) {
    final actions = widget.fields
        .where((f) => actionKeys.contains(f.key))
        .toList(growable: false);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final field in actions)
            XfActionButton(
              label: field.label.isEmpty ? '操作' : field.label,
              actionKind: (field.raw['actionKind'] ?? 'custom').toString(),
              onTap: widget.onAction == null ? null : () => widget.onAction!((field.raw['actionKind'] ?? 'custom').toString()),
            ),
        ],
      ),
    );
  }

  Widget _fieldWidget(XflowField field) {
    if (field.type == 'row') return _rowField(field);
    switch (field.type) {
      case 'section':
        return _sectionField(field);
      case 'pill':
        return _pillField(field, false);
      case 'multiSelect':
        return _pillField(field, true);
      case 'select':
        return _selectField(field);
      case 'computed':
        return _computedField(field);
      case 'level':
        return _levelField(field);
      case 'user':
        return _userField(field);
      case 'date':
        return _dateField(field);
      case 'dynamicList':
        return _dynamicListField(field);
      case 'structuredTable':
        return _structuredTableField(field);
      case 'matrix':
        return _matrixField(field);
      case 'upload':
        if (widget.service == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: XflowUploadField(
            field: field,
            service: widget.service!,
            items: normalizeUploadItems(widget.values[field.key]),
            onChanged: (items) => widget.onChanged(field.key, items),
          ),
        );
      case 'action':
        return const SizedBox.shrink();
      default:
        return _basicField(field);
    }
  }

  Widget _rowField(XflowField field) {
    final children = <XflowField>[];
    for (final key in field.children) {
      final child = widget.fields.where((f) => f.key == key).firstOrNull;
      if (child != null) children.add(child);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: _fieldWidget(children[i])),
          if (i != children.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _sectionField(XflowField field) {
    final tone = (field.raw['tone'] ?? field.raw['sectionStyle'] ?? '').toString();
    Color borderColor = DunesColors.accent;
    if (tone == 'green' || tone == 'fin') borderColor = DunesColors.green;
    if (tone == 'amber') borderColor = DunesColors.amber;
    if (tone == 'blue') borderColor = DunesColors.blue;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DunesColors.bgSoft, DunesColors.bgSoft.withValues(alpha: 0)],
          stops: const [0, 0.8],
        ),
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Text(
        field.label.isEmpty ? '分组' : field.label,
        style: DunesTypography.sans(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, bool readonly = false, bool mono = false}) {
    return xfInputDecoration(hint: hint, readonly: readonly, mono: mono);
  }

  Widget _selectField(XflowField field) {
    final current = widget.values[field.key]?.toString() ?? '';
    return _fieldWrap(
      field,
      DropdownButtonFormField<String>(
        value: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: _inputDecoration(hint: field.placeholder.isEmpty ? '请选择' : field.placeholder),
        items: [
          for (final option in field.options)
            DropdownMenuItem(
              value: option.value,
              child: Text(option.label, style: DunesTypography.sans(fontSize: 11.5)),
            ),
        ],
        onChanged: field.readonly ? null : (v) => widget.onChanged(field.key, v ?? ''),
      ),
    );
  }

  Widget _levelField(XflowField field) {
    final current = widget.values[field.key]?.toString() ?? '';
    final levels = field.options.isNotEmpty
        ? field.options.map((o) => o.value).toList()
        : const ['S', 'A', 'B', 'C'];
    Color onColor(String lv) {
      switch (lv) {
        case 'S':
          return const Color(0xFFE85D4C);
        case 'A':
          return const Color(0xFFD4A017);
        case 'B':
          return const Color(0xFF3B6FD4);
        default:
          return const Color(0xFF2D8A5E);
      }
    }

    return _fieldWrap(
      field,
      Row(
        children: [
          for (final lv in levels)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: lv == levels.last ? 0 : 3),
                child: InkWell(
                  onTap: field.readonly ? null : () => widget.onChanged(field.key, lv),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: current == lv ? onColor(lv) : DunesColors.bgSoft,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: current == lv ? onColor(lv) : DunesColors.border,
                      ),
                    ),
                    child: Text(
                      lv,
                      style: DunesTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: current == lv ? Colors.white : DunesColors.text2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _basicField(XflowField field) {
    final value = widget.values[field.key];
    final keyboardType = switch (field.type) {
      'number' || 'money' => const TextInputType.numberWithOptions(decimal: true),
      _ => TextInputType.text,
    };
    final maxLines = field.type == 'textarea' ? 5 : 1;
    return _fieldWrap(
      field,
      _XflowTextField(
        // 稳定 key：仅随字段标识变化，绝不随输入值变化，
        // 否则每输入一个字符都会重建输入框、丢失焦点（iOS 表现为键盘/输入框关闭）。
        key: ValueKey('field_${field.key}'),
        value: value?.toString() ?? '',
        keyboardType: keyboardType,
        minLines: 1,
        maxLines: maxLines,
        readOnly: field.readonly,
        style: field.type == 'money' || field.type == 'number'
            ? xfInputTextStyle(mono: true)
            : xfInputTextStyle(),
        decoration: _inputDecoration(hint: field.placeholder, readonly: field.readonly),
        onChanged: (text) => widget.onChanged(field.key, text),
      ),
    );
  }

  Widget _dateField(XflowField field) {
    final raw = widget.values[field.key]?.toString() ?? '';
    DateTime? date;
    if (raw.isNotEmpty) date = DateTime.tryParse(raw);
    final label = date == null
        ? (field.placeholder.isEmpty ? '年 / 月 / 日' : field.placeholder)
        : '${date.year} / ${date.month.toString().padLeft(2, '0')} / ${date.day.toString().padLeft(2, '0')}';
    return _fieldWrap(
      field,
      InkWell(
        onTap: field.readonly
            ? null
            : () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? now,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) {
                  widget.onChanged(
                    field.key,
                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
                  );
                }
              },
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: _inputDecoration(hint: field.placeholder),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    color: date == null ? DunesColors.text3 : DunesColors.text,
                  ),
                ),
              ),
              const Icon(Icons.calendar_today_outlined, size: 14, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _computedField(XflowField field) {
    final text = widget.values[field.key]?.toString() ?? '';
    return _fieldWrap(
      field,
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DunesColors.accentLine),
        ),
        child: Text(
          text.isEmpty ? '—' : text,
          style: DunesTypography.mono(fontSize: 13, color: DunesColors.text2),
        ),
      ),
    );
  }

  Widget _userField(XflowField field) {
    return _fieldWrap(
      field,
      _XflowUserPicker(
        service: widget.service,
        value: widget.values[field.key],
        placeholder: field.placeholder.isEmpty ? '搜索姓名/部门' : field.placeholder,
        readonly: field.readonly,
        onChanged: (v) => widget.onChanged(field.key, v),
      ),
    );
  }

  List<Map<String, dynamic>> _listValue(String key) {
    final raw = widget.values[key];
    if (raw is List) {
      return raw
          .map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map))
          .toList(growable: true);
    }
    if (raw is Map) return [Map<String, dynamic>.from(raw)];
    return <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _columns(XflowField field) {
    final raw = field.raw['columns'];
    if (raw is! List || raw.isEmpty) {
      return [
        {'key': 'col1', 'label': '列1', 'type': 'text'},
      ];
    }
    return raw
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList(growable: false);
  }

  Widget _dynamicListField(XflowField field) {
    final rows = _listValue(field.key);
    final cols = _columns(field);
    return _fieldWrap(
      field,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isNotEmpty)
            Column(
              children: [
                for (var ri = 0; ri < rows.length; ri++)
                  _dynRow(field.key, cols, rows, ri, onRemove: () {
                    rows.removeAt(ri);
                    widget.onChanged(field.key, rows);
                    setState(() {});
                  }),
              ],
            ),
          _addRowButton('+ 添加一行', () {
            rows.add(_emptyRow(cols));
            widget.onChanged(field.key, rows);
            setState(() {});
          }),
        ],
      ),
    );
  }

  Widget _structuredTableField(XflowField field) {
    final rows = _listValue(field.key);
    final cols = _columns(field);
    final nestedKey = (field.raw['nestedKey'] ?? 'items').toString();
    final nestedCols = _nestedColumns(field);
    return _fieldWrap(
      field,
      Column(
        children: [
          for (var ri = 0; ri < rows.length; ri++)
            _structRow(field, cols, nestedKey, nestedCols, rows, ri),
          _addRowButton('+ 添加供货商', () {
            rows.add(_emptyRow(cols));
            widget.onChanged(field.key, rows);
            setState(() {});
          }),
        ],
      ),
    );
  }

  Widget _structRow(
    XflowField field,
    List<Map<String, dynamic>> cols,
    String nestedKey,
    List<Map<String, dynamic>> nestedCols,
    List<Map<String, dynamic>> rows,
    int ri,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final col in cols)
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _dynCell(field.key, col, rows, ri, null, -1),
                    ),
                  ),
                ),
              XfRemoveButton(
                onTap: () {
                  rows.removeAt(ri);
                  widget.onChanged(field.key, rows);
                  setState(() {});
                },
              ),
            ],
          ),
          if (nestedCols.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '达量阶梯 · 机构保费',
              style: DunesTypography.sans(fontSize: 10, fontWeight: FontWeight.w600, color: DunesColors.text3),
            ),
            const SizedBox(height: 4),
            ..._nestedRows(field.key, nestedKey, nestedCols, rows, ri),
            XfAddRowButton(
              label: '+ 添加档位',
              onTap: () {
                final tiers = rows[ri].putIfAbsent(nestedKey, () => <dynamic>[]);
                if (tiers is List) {
                  tiers.add(_emptyRow(nestedCols));
                  widget.onChanged(field.key, rows);
                  setState(() {});
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _nestedColumns(XflowField field) {
    final raw = field.raw['nestedColumns'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList(growable: false);
  }

  List<Widget> _nestedRows(
    String fieldKey,
    String nestedKey,
    List<Map<String, dynamic>> nestedCols,
    List<Map<String, dynamic>> rows,
    int ri,
  ) {
    final tiersRaw = rows[ri][nestedKey];
    final tiers = tiersRaw is List
        ? tiersRaw.map((e) => e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    return [
      for (var ti = 0; ti < tiers.length; ti++)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final col in nestedCols)
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _dynCell(fieldKey, col, tiers, ti, nestedKey, ri),
                    ),
                  ),
                ),
              XfRemoveButton(
                size: 28,
                onTap: () {
                  tiers.removeAt(ti);
                  rows[ri][nestedKey] = tiers;
                  widget.onChanged(fieldKey, rows);
                  setState(() {});
                },
              ),
            ],
          ),
        ),
    ];
  }

  Widget _matrixField(XflowField field) {
    final rows = _listValue(field.key);
    final cols = _columns(field);
    return _fieldWrap(
      field,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: DunesColors.borderSoft),
              ),
              child: Table(
                border: TableBorder.all(color: DunesColors.borderSoft, width: 1),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: {
                  for (var i = 0; i < cols.length; i++)
                    i: const FlexColumnWidth(1),
                  cols.length: const FixedColumnWidth(36),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: DunesColors.bgSoft),
                    children: [
                      for (final col in cols)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          child: Text(
                            (col['label'] ?? col['key'] ?? '').toString(),
                            style: DunesTypography.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.text,
                            ),
                          ),
                        ),
                      const SizedBox.shrink(),
                    ],
                  ),
                  for (var ri = 0; ri < rows.length; ri++)
                    TableRow(
                      children: [
                        for (final col in cols)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: _matrixCellInput(field.key, col, rows, ri),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Center(
                            child: XfRemoveButton(
                              size: 28,
                              onTap: () {
                                rows.removeAt(ri);
                                widget.onChanged(field.key, rows);
                                setState(() {});
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          _addRowButton('+ 添加一行', () {
            rows.add(_emptyRow(cols));
            widget.onChanged(field.key, rows);
            setState(() {});
          }),
        ],
      ),
    );
  }

  Widget _matrixCellInput(
    String fieldKey,
    Map<String, dynamic> col,
    List<Map<String, dynamic>> rows,
    int ri,
  ) {
    final colKey = (col['key'] ?? '').toString();
    final value = rows[ri][colKey]?.toString() ?? '';
    return TextFormField(
      key: ValueKey('matrix_${fieldKey}_${ri}_$colKey'),
      initialValue: value,
      style: DunesTypography.sans(fontSize: 11, color: DunesColors.text),
      decoration: xfMatrixCellDecoration(hint: col['placeholder']?.toString()),
      onChanged: (v) {
        rows[ri][colKey] = v;
        widget.onChanged(fieldKey, rows);
      },
    );
  }

  Map<String, dynamic> _emptyRow(List<Map<String, dynamic>> cols) {
    final row = <String, dynamic>{};
    for (final col in cols) {
      row[(col['key'] ?? '').toString()] = '';
    }
    return row;
  }

  Widget _dynRow(
    String fieldKey,
    List<Map<String, dynamic>> cols,
    List<Map<String, dynamic>> rows,
    int ri, {
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.borderSoft.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final col in cols)
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 60),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _dynCell(fieldKey, col, rows, ri, null, -1),
                ),
              ),
            ),
          XfRemoveButton(onTap: onRemove),
        ],
      ),
    );
  }

  Widget _dynCell(
    String fieldKey,
    Map<String, dynamic> col,
    List<Map<String, dynamic>> rows,
    int ri,
    String? nestedKey,
    int parentRi, {
    bool matrix = false,
  }) {
    final colKey = (col['key'] ?? '').toString();
    final label = (col['label'] ?? colKey).toString();
    final value = rows[ri][colKey]?.toString() ?? '';
    void setVal(String v) {
      rows[ri][colKey] = v;
      if (nestedKey != null && parentRi >= 0) {
        final parent = _listValue(fieldKey);
        if (parentRi < parent.length) {
          parent[parentRi][nestedKey] = rows;
          widget.onChanged(fieldKey, parent);
        }
      } else {
        widget.onChanged(fieldKey, rows);
      }
      setState(() {});
    }

    final decoration = matrix
        ? xfMatrixCellDecoration(hint: col['placeholder']?.toString())
        : xfDynCellDecoration(hint: col['placeholder']?.toString());

    final input = col['type']?.toString() == 'select'
        ? DropdownButtonFormField<String>(
            value: value.isEmpty ? null : value,
            isExpanded: true,
            decoration: decoration,
            style: xfDynInputTextStyle(),
            dropdownColor: Colors.white,
            items: [
              for (final o in _colOptions(col))
                DropdownMenuItem(
                  value: o.value,
                  child: Text(o.label, style: xfDynInputTextStyle().copyWith(fontSize: 11)),
                ),
            ],
            onChanged: (v) => setVal(v ?? ''),
          )
        : TextFormField(
            key: ValueKey('dyn_${fieldKey}_${ri}_$colKey'),
            initialValue: value,
            decoration: decoration,
            style: matrix ? DunesTypography.sans(fontSize: 11, color: DunesColors.text) : xfDynInputTextStyle(),
            onChanged: setVal,
          );

    if (matrix) return input;

    return XfDynCell(label: label, child: input);
  }

  List<XflowFieldOption> _colOptions(Map<String, dynamic> col) {
    final raw = col['options'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((o) => XflowFieldOption.fromJson(Map<String, dynamic>.from(o)))
        .toList(growable: false);
  }

  Widget _addRowButton(String label, VoidCallback onTap) {
    return XfAddRowButton(label: label, onTap: onTap);
  }

  Widget _pillField(XflowField field, bool multi) {
    final current = widget.values[field.key];
    final selected = <String>{};
    if (current is List) {
      for (final e in current) {
        selected.add(e.toString());
      }
    } else if (current != null && current.toString().isNotEmpty) {
      selected.add(current.toString());
    }
    final isProvinceGrid =
        field.raw['layout']?.toString() == 'provinceGrid' || field.raw['dictKey']?.toString() == 'provinces';
    return _fieldWrap(
      field,
      isProvinceGrid
          ? GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 2.4,
              children: [
                for (final option in field.options)
                  _pill(
                    text: option.label,
                    selected: selected.contains(option.value),
                    compact: true,
                    onTap: () => _togglePill(field.key, option.value, multi, selected),
                  ),
              ],
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in field.options)
                  _pill(
                    text: option.label,
                    selected: selected.contains(option.value),
                    onTap: () => _togglePill(field.key, option.value, multi, selected),
                  ),
              ],
            ),
    );
  }

  void _togglePill(String key, String value, bool multi, Set<String> selected) {
    final next = <String>{...selected};
    if (multi) {
      if (next.contains(value)) {
        next.remove(value);
      } else {
        next.add(value);
      }
      widget.onChanged(key, next.toList(growable: false));
    } else {
      if (next.contains(value)) {
        widget.onChanged(key, '');
      } else {
        widget.onChanged(key, value);
      }
    }
    setState(() {});
  }

  Widget _pill({
    required String text,
    required bool selected,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 10, vertical: compact ? 5 : 5),
        decoration: BoxDecoration(
          color: selected ? DunesColors.accentSoft : DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: selected ? DunesColors.accent : DunesColors.border),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: DunesTypography.sans(
            fontSize: compact ? 10 : 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? DunesColors.accentDeep : DunesColors.text2,
          ),
        ),
      ),
    );
  }

  Widget _fieldWrap(XflowField field, Widget child) {
    final label = field.label.isEmpty ? field.key : field.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XfFieldLabel(label: label, required: field.required),
        child,
      ],
    );
  }

  bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is Map && (v['userId'] != null || v['id'] != null || v['name'] != null)) return true;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }
}

class _XflowUserPicker extends StatefulWidget {
  const _XflowUserPicker({
    required this.service,
    required this.value,
    required this.placeholder,
    required this.readonly,
    required this.onChanged,
  });

  final XflowService? service;
  final dynamic value;
  final String placeholder;
  final bool readonly;
  final void Function(dynamic value) onChanged;

  @override
  State<_XflowUserPicker> createState() => _XflowUserPickerState();
}

class _XflowUserPickerState extends State<_XflowUserPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _controller.text = _displayName(widget.value);
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _XflowUserPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _displayName(widget.value);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _displayName(dynamic val) {
    if (val is Map) {
      return (val['name'] ?? val['displayName'] ?? '').toString();
    }
    return val?.toString() ?? '';
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), _removeOverlay);
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _search(String q) async {
    if (widget.service == null || q.trim().isEmpty) {
      setState(() => _results = const []);
      _removeOverlay();
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await widget.service!.searchOrgUsers(q);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
      _showOverlay();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showDunesToast(context, '人员搜索失败', kind: DunesToastKind.error);
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (_results.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    _overlay = OverlayEntry(
      builder: (ctx) => Positioned(
        left: offset.dx,
        top: offset.dy + box.size.height + 4,
        width: box.size.width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final u in _results.take(8))
                  ListTile(
                    dense: true,
                    title: Text(
                      '${u['displayName'] ?? u['name'] ?? ''}${u['departmentName'] != null ? ' · ${u['departmentName']}' : ''}',
                      style: DunesTypography.sans(fontSize: 11.5),
                    ),
                    onTap: () {
                      widget.onChanged({
                        'userId': u['userId'] ?? u['id'],
                        'name': u['displayName'] ?? u['name'],
                        'dept': u['departmentName'] ?? u['dept'] ?? '',
                        'title': u['title'] ?? '',
                      });
                      _controller.text = (u['displayName'] ?? u['name'] ?? '').toString();
                      _removeOverlay();
                      _focus.unfocus();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      readOnly: widget.readonly,
      decoration: xfInputDecoration(hint: widget.placeholder).copyWith(
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : null,
      ),
      style: xfInputTextStyle(),
      onChanged: (q) {
        Future.delayed(const Duration(milliseconds: 220), () {
          if (_controller.text.trim() == q.trim()) _search(q);
        });
      },
    );
  }
}

/// 受控文本输入：内部持有 controller，避免父级在每次 onChanged 后重建
/// 导致输入框丢焦点。仅当外部 value 与当前输入不一致（如导入/AI 填充）时同步。
class _XflowTextField extends StatefulWidget {
  const _XflowTextField({
    super.key,
    required this.value,
    required this.keyboardType,
    required this.minLines,
    required this.maxLines,
    required this.readOnly,
    required this.style,
    required this.decoration,
    required this.onChanged,
  });

  final String value;
  final TextInputType keyboardType;
  final int minLines;
  final int maxLines;
  final bool readOnly;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  @override
  State<_XflowTextField> createState() => _XflowTextFieldState();
}

class _XflowTextFieldState extends State<_XflowTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _XflowTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化（导入 / AI 填充 / 重置）时同步到输入框；
    // 用户自己输入时 value 已与 controller 一致，不会触发，故不会打断输入。
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: widget.keyboardType,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly,
      style: widget.style,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}

extension on Iterable<XflowField> {
  XflowField? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
