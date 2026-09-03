import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'xflow_bill_cascade_field.dart';
import 'xflow_detail_logic.dart';
import 'xflow_form_styles.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';
import 'xflow_upload_field.dart';

typedef XflowFieldChanged = void Function(String key, dynamic value);
typedef XflowFormAction = Future<void> Function(String actionKind);
typedef XflowFieldOverride = Widget? Function(XflowField field);

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
    this.allowedActionKinds,
    this.showProgressCard = true,
    this.showActionBar = true,
    this.fieldOverride,
  });

  final List<XflowField> fields;
  final Map<String, dynamic> values;
  final XflowFieldChanged onChanged;
  final Map<String, dynamic> layout;
  final XflowService? service;
  final XflowFormAction? onAction;
  final bool embedded;
  final Set<String>? allowedActionKinds;
  final bool showProgressCard;
  final bool showActionBar;
  final XflowFieldOverride? fieldOverride;

  @override
  State<XflowFormRenderer> createState() => _XflowFormRendererState();
}

class _XflowFormRendererState extends State<XflowFormRenderer> {
  final Set<String> _cardMinPadScheduled = <String>{};

  void _dismissKeyboardOnTapOutside(PointerDownEvent _) {
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
        if (widget.showProgressCard) _progressCard(),
        if (widget.showActionBar) _actionBar(actionKeys),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: XfProposalUi.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: XfProposalUi.lineSoft),
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

  ({int pct, int bizDone, int bizTotal, int finDone, int finTotal})
  _progress() {
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
    return (
      pct: pct,
      bizDone: bizDone,
      bizTotal: biz.length,
      finDone: finDone,
      finTotal: fin.length,
    );
  }

  List<String> _keyList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  Widget _progressCard() {
    final p = _progress();
    if (p.bizTotal + p.finTotal == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: XfProposalUi.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: XfProposalUi.line),
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
              color: XfProposalUi.coral,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '业务 ${p.bizDone} / ${p.bizTotal}',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '财务 ${p.finDone} / ${p.finTotal}',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    color: DunesColors.text3,
                  ),
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
        .where((f) {
          final kind = (f.raw['actionKind'] ?? f.key).toString();
          final allowed = widget.allowedActionKinds;
          return allowed == null || allowed.contains(kind);
        })
        .toList(growable: false);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: XfProposalUi.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: XfProposalUi.line),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final field in actions)
            XfActionButton(
              label: field.label.isEmpty ? '操作' : field.label,
              actionKind: (field.raw['actionKind'] ?? 'custom').toString(),
              onTap: widget.onAction == null
                  ? null
                  : () => widget.onAction!(
                      (field.raw['actionKind'] ?? 'custom').toString(),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _fieldWidget(XflowField field, {bool inRow = false}) {
    final override = widget.fieldOverride?.call(field);
    if (override != null) return override;
    if (field.type == 'row') return _rowField(field);
    if (_isUserField(field)) return _userField(field, inRow: inRow);
    if (field.type == 'proposal') return _proposalField(field, inRow: inRow);
    if (_isRemoteSearchField(field)) {
      return _remoteSearchField(field, inRow: inRow);
    }
    if (field.type == 'billCascade') {
      return _fieldWrap(
        field,
        XflowBillCascadeField(
          field: field,
          value: widget.values[field.key],
          service: widget.service,
          readonly: field.readonly,
          onChanged: (v) => widget.onChanged(field.key, v),
        ),
        inRow: inRow,
      );
    }
    switch (field.type) {
      case 'section':
        return _sectionField(field);
      case 'pill':
        return _pillField(field, false, inRow: inRow);
      case 'multiSelect':
        return _pillField(field, true, inRow: inRow);
      case 'select':
        return _selectField(field, inRow: inRow);
      case 'computed':
        return _computedField(field, inRow: inRow);
      case 'level':
        return _levelField(field, inRow: inRow);
      case 'user':
      case 'userSelect':
        return _userField(field, inRow: inRow);
      case 'date':
        return _dateField(field, inRow: inRow);
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
        return _basicField(field, inRow: inRow);
    }
  }

  Widget _rowField(XflowField field) {
    final children = <XflowField>[];
    for (final key in field.children) {
      final child = widget.fields.where((f) => f.key == key).firstOrNull;
      if (child != null) children.add(child);
    }
    if (children.isEmpty) return const SizedBox.shrink();

    final connector = (field.raw['connector'] ?? '').toString().trim();
    final maxPerRow = _rowMaxColumns(field, children);

    if (children.length <= maxPerRow) {
      return _rowChunk(children, connector: connector);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < children.length; start += maxPerRow)
          Padding(
            padding: EdgeInsets.only(
              bottom: start + maxPerRow < children.length ? 8 : 0,
            ),
            child: _rowChunk(
              children.sublist(
                start,
                start + maxPerRow > children.length
                    ? children.length
                    : start + maxPerRow,
              ),
              connector: connector.isNotEmpty && start == 0 ? connector : '',
            ),
          ),
      ],
    );
  }

  int _rowMaxColumns(XflowField field, List<XflowField> children) {
    final fromRaw = field.raw['maxPerRow'] ?? field.raw['columns'];
    if (fromRaw is num && fromRaw.toInt() > 0) return fromRaw.toInt();
    if (fromRaw is String) {
      final parsed = int.tryParse(fromRaw);
      if (parsed != null && parsed > 0) return parsed;
    }
    if (children.isNotEmpty &&
        children.every((c) => c.type == 'date') &&
        children.length > 2) {
      return 2;
    }
    return children.length;
  }

  Widget _rowChunk(List<XflowField> children, {required String connector}) {
    if (children.length == 1) {
      return _fieldWidget(children.first, inRow: false);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: _fieldWidget(children[i], inRow: true)),
          if (connector.isNotEmpty && i < children.length - 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                connector,
                style: DunesTypography.mono(
                  fontSize: 11,
                  color: DunesColors.text3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (i != children.length - 1)
            const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _sectionField(XflowField field) {
    final tone = (field.raw['tone'] ?? field.raw['sectionStyle'] ?? '')
        .toString();
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

  InputDecoration _inputDecoration({
    String? hint,
    bool readonly = false,
    bool mono = false,
  }) {
    return xfInputDecoration(hint: hint, readonly: readonly, mono: mono);
  }

  Widget _selectField(XflowField field, {bool inRow = false}) {
    final current = widget.values[field.key]?.toString() ?? '';
    return _fieldWrap(
      field,
      _XflowSelectPicker(
        options: field.options,
        value: current,
        placeholder: field.placeholder.isEmpty ? '请选择' : field.placeholder,
        readonly: field.readonly,
        onChanged: (v) => widget.onChanged(field.key, v),
      ),
      inRow: inRow,
    );
  }

  Widget _levelField(XflowField field, {bool inRow = false}) {
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
                  onTap: field.readonly
                      ? null
                      : () => widget.onChanged(field.key, lv),
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
      inRow: inRow,
    );
  }

  Widget _basicField(XflowField field, {bool inRow = false}) {
    final value = widget.values[field.key];
    final keyboardType = switch (field.type) {
      'number' ||
      'money' => const TextInputType.numberWithOptions(decimal: true),
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
        decoration: _inputDecoration(
          hint: field.placeholder,
          readonly: field.readonly,
        ),
        onChanged: (text) => widget.onChanged(field.key, text),
      ),
      inRow: inRow,
    );
  }

  Widget _dateField(XflowField field, {bool inRow = false}) {
    final raw = widget.values[field.key]?.toString() ?? '';
    DateTime? date;
    if (raw.isNotEmpty) date = DateTime.tryParse(raw);
    final readonly = field.readonly;
    final autoHint = (field.raw['hint'] ?? '').toString().trim();
    final label = date == null
        ? (readonly
              ? '待流程写入'
              : (field.placeholder.isEmpty ? '年 / 月 / 日' : field.placeholder))
        : '${date.year} / ${date.month.toString().padLeft(2, '0')} / ${date.day.toString().padLeft(2, '0')}';
    final decoration = _inputDecoration(
      hint: readonly ? null : field.placeholder,
      readonly: readonly,
    );
    final control = xfFixedHeightControl(
      child: InputDecorator(
        decoration: decoration,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: xfInputTextStyle().copyWith(
                  color: date == null
                      ? DunesColors.text3
                      : (readonly ? DunesColors.text2 : DunesColors.text),
                ),
              ),
            ),
            Icon(
              readonly
                  ? Icons.lock_clock_outlined
                  : Icons.calendar_today_outlined,
              size: 14,
              color: readonly
                  ? DunesColors.text3.withValues(alpha: 0.65)
                  : DunesColors.text3,
            ),
          ],
        ),
      ),
    );
    return _fieldWrap(
      field,
      readonly
          ? control
          : InkWell(
              onTap: () async {
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
              borderRadius: BorderRadius.circular(9),
              child: control,
            ),
      inRow: inRow,
      hint: readonly && autoHint.isNotEmpty ? autoHint : null,
    );
  }

  Widget _computedField(XflowField field, {bool inRow = false}) {
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
      inRow: inRow,
    );
  }

  bool _isUserField(XflowField field) {
    if (field.type == 'user' || field.type == 'userSelect') return true;
    return field.raw['dataSource']?.toString() == 'org_user';
  }

  bool _isRemoteSearchField(XflowField field) => field.remoteSearch != null;

  String? _userRoleFilter(XflowField field) {
    final raw = field.raw;
    for (final key in ['roleCode', 'allowedRole', 'userRoleCode']) {
      final v = (raw[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    // 技术负责人：仅可选 TECH 审批角色
    if (field.key == 'respTech') return 'TECH';
    return null;
  }

  Widget _proposalField(XflowField field, {bool inRow = false}) {
    final hint = field.placeholder.isEmpty ? '搜索已完成的协作提案' : field.placeholder;
    return _fieldWrap(
      field,
      _XflowProposalPicker(
        service: widget.service,
        value: widget.values[field.key],
        placeholder: hint,
        readonly: field.readonly,
        onChanged: (v) => widget.onChanged(field.key, v),
      ),
      inRow: inRow,
    );
  }

  Widget _remoteSearchField(XflowField field, {bool inRow = false}) {
    final cfg = field.remoteSearch!;
    final hint = field.placeholder.isEmpty ? '输入关键词搜索' : field.placeholder;
    return _fieldWrap(
      field,
      _XflowRemoteSearchPicker(
        service: widget.service,
        config: cfg,
        fieldKey: field.key,
        value: widget.values[field.key],
        placeholder: hint,
        readonly: field.readonly,
        onFieldChanged: widget.onChanged,
      ),
      inRow: inRow,
    );
  }

  Widget _userField(XflowField field, {bool inRow = false}) {
    final roleCode = _userRoleFilter(field);
    final hint = field.placeholder.isEmpty
        ? (roleCode == 'TECH' ? '搜索技术审批人' : '搜索姓名/部门')
        : field.placeholder;
    return _fieldWrap(
      field,
      _XflowUserPicker(
        service: widget.service,
        value: widget.values[field.key],
        placeholder: hint,
        readonly: field.readonly,
        roleCode: roleCode,
        onChanged: (v) => widget.onChanged(field.key, v),
      ),
      inRow: inRow,
    );
  }

  List<Map<String, dynamic>> _listValue(String key) {
    final raw = widget.values[key];
    if (raw is List) {
      return raw
          .map(
            (e) => e is Map<String, dynamic>
                ? e
                : Map<String, dynamic>.from(e as Map),
          )
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
    if (field.isCardDynamicList) {
      return _repeatableGroupField(field);
    }
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
                  _dynRow(
                    field.key,
                    cols,
                    rows,
                    ri,
                    onRemove: () {
                      rows.removeAt(ri);
                      widget.onChanged(field.key, rows);
                      setState(() {});
                    },
                  ),
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
              style: DunesTypography.sans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 4),
            ..._nestedRows(field.key, nestedKey, nestedCols, rows, ri),
            XfAddRowButton(
              label: '+ 添加档位',
              onTap: () {
                final tiers = rows[ri].putIfAbsent(
                  nestedKey,
                  () => <dynamic>[],
                );
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
    return raw
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList(growable: false);
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
        ? tiersRaw
              .map(
                (e) => e is Map<String, dynamic>
                    ? e
                    : Map<String, dynamic>.from(e as Map),
              )
              .toList()
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
                border: TableBorder.all(
                  color: DunesColors.borderSoft,
                  width: 1,
                ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
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
      onTapOutside: _dismissKeyboardOnTapOutside,
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

  void _scheduleCardMinItems(String fieldKey, List<Map<String, dynamic>> groups) {
    if (_cardMinPadScheduled.contains(fieldKey)) return;
    _cardMinPadScheduled.add(fieldKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cardMinPadScheduled.remove(fieldKey);
      if (!mounted) return;
      widget.onChanged(fieldKey, groups);
    });
  }

  Widget _repeatableGroupField(XflowField field) {
    final min = field.minItems;
    var groups = _listValue(field.key);
    if (groups.length < min) {
      groups = [
        ...groups.map(Map<String, dynamic>.from),
        ...List.generate(min - groups.length, (_) => <String, dynamic>{}),
      ];
      _scheduleCardMinItems(field.key, groups);
    }
    final canRemove = groups.length > min;
    return _fieldWrap(
      field,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groups.length; i++)
            _repeatableGroupCard(field, groups, i, canRemove: canRemove),
          _addRowButton('+ ${field.addText}', () {
            widget.onChanged(field.key, [
              ...groups.map(Map<String, dynamic>.from),
              <String, dynamic>{},
            ]);
            setState(() {});
          }),
        ],
      ),
    );
  }

  Widget _repeatableGroupCard(
    XflowField field,
    List<Map<String, dynamic>> groups,
    int index, {
    required bool canRemove,
  }) {
    final cols = field.columnsAsFields;
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
                  '${field.itemTitle}${index + 1}',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (canRemove)
                XfRemoveButton(
                  onTap: () {
                    final next = [
                      for (var i = 0; i < groups.length; i++)
                        if (i != index) Map<String, dynamic>.from(groups[i]),
                    ];
                    widget.onChanged(field.key, next);
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final col in cols)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _groupColumnField(field, col, groups, index),
            ),
        ],
      ),
    );
  }

  Widget _groupColumnField(
    XflowField listField,
    XflowField col,
    List<Map<String, dynamic>> groups,
    int index,
  ) {
    void patch(Map<String, dynamic> updates) {
      final next = [
        for (var i = 0; i < groups.length; i++)
          i == index
              ? <String, dynamic>{...groups[i], ...updates}
              : Map<String, dynamic>.from(groups[i]),
      ];
      widget.onChanged(listField.key, next);
      setState(() {});
    }

    final group = index < groups.length ? groups[index] : <String, dynamic>{};
    if (col.remoteSearch != null) {
      final cfg = col.remoteSearch!;
      final hint = col.placeholder.isEmpty ? '输入关键词搜索' : col.placeholder;
      return _fieldWrap(
        col,
        _XflowRemoteSearchPicker(
          service: widget.service,
          config: cfg,
          fieldKey: col.key,
          value: group[col.key],
          placeholder: hint,
          readonly: col.readonly,
          scopeValues: group,
          onPatch: patch,
          onFieldChanged: (key, value) => patch({key: value}),
        ),
      );
    }
    if (col.type == 'upload') {
      if (widget.service == null) return const SizedBox.shrink();
      return XflowUploadField(
        field: col,
        service: widget.service!,
        items: normalizeUploadItems(group[col.key]),
        onChanged: (items) => patch({col.key: items}),
      );
    }
    if (col.type == 'select') {
      return _fieldWrap(
        col,
        _XflowSelectPicker(
          options: col.options,
          value: group[col.key]?.toString() ?? '',
          placeholder: col.placeholder.isEmpty ? '请选择' : col.placeholder,
          readonly: col.readonly,
          onChanged: (v) => patch({col.key: v}),
        ),
      );
    }
    final keyboardType = switch (col.type) {
      'number' ||
      'money' => const TextInputType.numberWithOptions(decimal: true),
      _ => TextInputType.text,
    };
    return _fieldWrap(
      col,
      _XflowTextField(
        key: ValueKey('group_${listField.key}_${index}_${col.key}'),
        value: group[col.key]?.toString() ?? '',
        keyboardType: keyboardType,
        minLines: 1,
        maxLines: col.type == 'textarea' ? 5 : 1,
        readOnly: col.readonly,
        style: col.type == 'money' || col.type == 'number'
            ? xfInputTextStyle(mono: true)
            : xfInputTextStyle(),
        decoration: _inputDecoration(
          hint: col.placeholder,
          readonly: col.readonly,
        ),
        onChanged: (text) => patch({col.key: text}),
      ),
    );
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
        border: Border.all(
          color: DunesColors.borderSoft.withValues(alpha: 0.6),
        ),
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
                  child: Text(
                    o.label,
                    style: xfDynInputTextStyle().copyWith(fontSize: 11),
                  ),
                ),
            ],
            onChanged: (v) => setVal(v ?? ''),
          )
        : TextFormField(
            key: ValueKey('dyn_${fieldKey}_${ri}_$colKey'),
            initialValue: value,
            decoration: decoration,
            style: matrix
                ? DunesTypography.sans(fontSize: 11, color: DunesColors.text)
                : xfDynInputTextStyle(),
            onTapOutside: _dismissKeyboardOnTapOutside,
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

  Widget _pillField(XflowField field, bool multi, {bool inRow = false}) {
    if (multi && (field.raw['allowCustom'] == true || field.options.isEmpty)) {
      return _customTagsField(field, inRow: inRow);
    }
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
        field.raw['layout']?.toString() == 'provinceGrid' ||
        field.raw['dictKey']?.toString() == 'provinces';
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
                    onTap: () =>
                        _togglePill(field.key, option.value, multi, selected),
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
                    onTap: () =>
                        _togglePill(field.key, option.value, multi, selected),
                  ),
              ],
            ),
      inRow: inRow,
    );
  }

  Widget _customTagsField(XflowField field, {bool inRow = false}) {
    final raw = widget.values[field.key];
    final tags = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final text = item.toString().trim();
        if (text.isNotEmpty) tags.add(text);
      }
    } else if (raw != null && raw.toString().trim().isNotEmpty) {
      tags.add(raw.toString().trim());
    }

    void addTag(String text) {
      final next = text.trim();
      if (next.isEmpty || tags.contains(next)) return;
      final updated = [...tags, next];
      widget.onChanged(field.key, updated);
      setState(() {});
    }

    void removeTag(String text) {
      final updated = tags.where((tag) => tag != text).toList(growable: false);
      widget.onChanged(field.key, updated);
      setState(() {});
    }

    return _fieldWrap(
      field,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in tags)
                    InputChip(
                      label: Text(
                        tag,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.accentDeep,
                        ),
                      ),
                      deleteIcon: field.readonly
                          ? null
                          : const Icon(
                              Icons.close,
                              size: 14,
                              color: DunesColors.text3,
                            ),
                      onDeleted: field.readonly ? null : () => removeTag(tag),
                      backgroundColor: DunesColors.accentSoft,
                      side: const BorderSide(color: DunesColors.accentLine),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          if (!field.readonly)
            _XflowTagInput(
              key: ValueKey('tags_input_${field.key}'),
              hint: field.placeholder.isEmpty
                  ? '输入关键词后按回车添加'
                  : field.placeholder,
              onSubmit: addTag,
            )
          else if (tags.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: DunesColors.bgSoft,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: DunesColors.border),
              ),
              child: Text(
                field.placeholder.isEmpty ? '—' : field.placeholder,
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  color: DunesColors.text3,
                ),
              ),
            ),
        ],
      ),
      inRow: inRow,
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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 10,
          vertical: compact ? 5 : 5,
        ),
        decoration: BoxDecoration(
          color: selected ? DunesColors.accentSoft : DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? DunesColors.accent : DunesColors.border,
          ),
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

  Widget _fieldWrap(
    XflowField field,
    Widget child, {
    bool inRow = false,
    String? hint,
  }) {
    final label = field.label.isEmpty ? field.key : field.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        XfFieldLabel(label: label, required: field.required, compact: inRow),
        child,
        if (hint != null && hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 9.5,
                color: DunesColors.text3,
                height: 1.3,
              ),
            ),
          ),
      ],
    );
  }

  bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is Map &&
        (v['userId'] != null || v['id'] != null || v['name'] != null))
      return true;
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
    this.roleCode,
  });

  final XflowService? service;
  final dynamic value;
  final String placeholder;
  final bool readonly;
  final String? roleCode;
  final void Function(dynamic value) onChanged;

  @override
  State<_XflowUserPicker> createState() => _XflowUserPickerState();
}

class _XflowSelectPicker extends StatefulWidget {
  const _XflowSelectPicker({
    required this.options,
    required this.value,
    required this.placeholder,
    required this.readonly,
    required this.onChanged,
  });

  final List<XflowFieldOption> options;
  final String value;
  final String placeholder;
  final bool readonly;
  final ValueChanged<String> onChanged;

  @override
  State<_XflowSelectPicker> createState() => _XflowSelectPickerState();
}

class _XflowSelectPickerState extends State<_XflowSelectPicker> {
  final TextEditingController _controller = TextEditingController();
  List<XflowFieldOption> _filtered = const [];
  bool _touched = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller.text = _labelForValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant _XflowSelectPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.options != widget.options) {
      final next = _labelForValue(widget.value);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _labelForValue(String value) {
    if (value.trim().isEmpty) return '';
    for (final option in widget.options) {
      if (option.value == value) return option.label;
    }
    return value;
  }

  void _applyFilter(String query, {bool markTouched = true}) {
    final q = query.trim().toLowerCase();
    final out = q.isEmpty
        ? widget.options
        : widget.options.where((o) {
            final label = o.label.toLowerCase();
            final value = o.value.toLowerCase();
            return label.contains(q) || value.contains(q);
          }).toList(growable: false);
    setState(() {
      _filtered = out;
      if (markTouched) _touched = true;
    });
  }

  void _select(XflowFieldOption option) {
    widget.onChanged(option.value);
    setState(() {
      _controller.text = option.label;
      _filtered = const [];
      _touched = false;
      _expanded = false;
    });
  }

  void _clear() {
    widget.onChanged('');
    setState(() {
      _controller.clear();
      _filtered = widget.options;
      _touched = false;
      _expanded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final showMenu = !widget.readonly && _expanded && _filtered.isNotEmpty;
    return TapRegion(
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        if (_expanded) setState(() => _expanded = false);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          xfFixedHeightControl(
            child: TextField(
              controller: _controller,
              onTap: widget.readonly
                  ? null
                  : () {
                      if (!_expanded) {
                        setState(() => _expanded = true);
                        _applyFilter('', markTouched: false);
                      }
                    },
              readOnly: true,
              enableInteractiveSelection: false,
              style: xfInputTextStyle(),
              decoration: xfInputDecoration(
                hint: widget.placeholder,
                readonly: widget.readonly,
              ).copyWith(
                suffixIconConstraints: const BoxConstraints(minWidth: 72),
                suffixIcon: widget.readonly
                    ? const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: DunesColors.text3,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasText)
                            IconButton(
                              tooltip: '清除',
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: DunesColors.text3,
                              ),
                              onPressed: _clear,
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
                            onPressed: () {
                              if (_expanded) {
                                setState(() => _expanded = false);
                              } else {
                                setState(() => _expanded = true);
                                _applyFilter('', markTouched: false);
                              }
                            },
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
              itemCount: _filtered.length.clamp(0, 8),
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: DunesColors.borderSoft),
              itemBuilder: (context, index) {
                final option = _filtered[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    option.label,
                    style: DunesTypography.sans(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: DunesColors.text3,
                  ),
                  onTap: () => _select(option),
                );
              },
            ),
          ),
        ] else if (!widget.readonly &&
            _touched &&
            _expanded &&
            _controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '未找到匹配选项，请换个关键词',
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ],
        ],
      ),
    );
  }
}

class _XflowUserPickerState extends State<_XflowUserPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = _displayName(widget.value);
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus || widget.readonly) return;
    final role = widget.roleCode?.trim() ?? '';
    if (role.isEmpty) return;
    if (_controller.text.trim().isNotEmpty) return;
    if (_results.isNotEmpty || _loading) return;
    _search('');
  }

  @override
  void didUpdateWidget(covariant _XflowUserPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final next = _displayName(widget.value);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  void _clearSelection() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _results = const [];
      _searched = false;
      _loading = false;
    });
    widget.onChanged(null);
  }

  void _selectUser(Map<String, dynamic> u) {
    final name = (u['displayName'] ?? u['name'] ?? '').toString();
    widget.onChanged({
      'userId': u['userId'] ?? u['id'],
      'name': name,
      'dept': u['departmentName'] ?? u['dept'] ?? '',
      'title': u['title'] ?? '',
    });
    setState(() {
      _controller.text = name;
      _results = const [];
      _searched = false;
      _loading = false;
    });
    _focus.unfocus();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    final role = widget.roleCode?.trim() ?? '';
    if (widget.service == null || (query.isEmpty && role.isEmpty)) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await widget.service!.searchOrgUsers(
        query,
        roleCode: widget.roleCode,
      );
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = rows;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = const [];
      });
      showDunesToast(context, '人员搜索失败', kind: DunesToastKind.error);
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_controller.text.trim() == q.trim()) _search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          readOnly: widget.readonly,
          enableInteractiveSelection: true,
          contextMenuBuilder: (context, editableTextState) {
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          },
          decoration: xfInputDecoration(hint: widget.placeholder).copyWith(
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hasText && !widget.readonly
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                    onPressed: _clearSelection,
                    tooltip: '清除',
                  )
                : const Icon(
                    Icons.search,
                    size: 18,
                    color: DunesColors.text3,
                  ),
          ),
          style: xfInputTextStyle(),
          onChanged: widget.readonly ? null : _onQueryChanged,
        ),
        if (_results.isNotEmpty) ...[
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
              itemCount: _results.length.clamp(0, 8),
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: DunesColors.borderSoft),
              itemBuilder: (context, index) {
                final u = _results[index];
                final name = (u['displayName'] ?? u['name'] ?? '').toString();
                final dept = (u['departmentName'] ?? u['dept'] ?? '').toString();
                return ListTile(
                  dense: true,
                  title: Text(
                    dept.isEmpty ? name : '$name · $dept',
                    style: DunesTypography.sans(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 16,
                    color: DunesColors.text3,
                  ),
                  onTap: () => _selectUser(u),
                );
              },
            ),
          ),
        ] else if (_searched && !_loading && hasText) ...[
          const SizedBox(height: 6),
          Text(
            '未找到匹配人员，请换个关键词',
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ],
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
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

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
      enableInteractiveSelection: true,
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      },
      style: widget.style,
      decoration: widget.decoration,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onChanged: widget.onChanged,
    );
  }
}

class _XflowProposalPicker extends StatefulWidget {
  const _XflowProposalPicker({
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
  State<_XflowProposalPicker> createState() => _XflowProposalPickerState();
}

class _XflowProposalPickerState extends State<_XflowProposalPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = _displayText(widget.value);
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus || widget.readonly) return;
    if (_controller.text.trim().isNotEmpty) return;
    if (_results.isNotEmpty || _loading) return;
    _search('');
  }

  @override
  void didUpdateWidget(covariant _XflowProposalPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final next = _displayText(widget.value);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _displayText(dynamic val) {
    if (val is Map) {
      final code = (val['code'] ?? val['proposalCode'] ?? '').toString().trim();
      final title = (val['title'] ?? val['name'] ?? '').toString().trim();
      if (code.isNotEmpty && title.isNotEmpty) return '$code · $title';
      if (code.isNotEmpty) return code;
      if (title.isNotEmpty) return title;
    }
    return val?.toString() ?? '';
  }

  void _clearSelection() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _results = const [];
      _searched = false;
      _loading = false;
    });
    widget.onChanged(null);
  }

  void _selectProposal(Map<String, dynamic> row) {
    final id = _int(row['proposalId'] ?? row['id']);
    final code = (row['code'] ?? '').toString().trim();
    final title = (row['title'] ?? row['name'] ?? '').toString().trim();
    widget.onChanged(
      linkedProposalIntakePayload(id: id, code: code, title: title),
    );
    setState(() {
      _controller.text = code.isNotEmpty && title.isNotEmpty
          ? '$code · $title'
          : (code.isNotEmpty ? code : title);
      _results = const [];
      _searched = false;
      _loading = false;
    });
    _focus.unfocus();
  }

  int _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _search(String q) async {
    if (widget.service == null) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await widget.service!.searchCompletedProposalIntakes(q);
      if (!mounted || _controller.text.trim() != q.trim()) return;
      setState(() {
        _results = rows;
        _searched = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = const [];
      });
      showDunesToast(context, '提案搜索失败', kind: DunesToastKind.error);
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (_controller.text.trim() == q.trim()) _search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          readOnly: widget.readonly,
          decoration: xfInputDecoration(hint: widget.placeholder).copyWith(
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hasText && !widget.readonly
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                    onPressed: _clearSelection,
                    tooltip: '清除',
                  )
                : const Icon(
                    Icons.search,
                    size: 18,
                    color: DunesColors.text3,
                  ),
          ),
          style: xfInputTextStyle(),
          onChanged: widget.readonly ? null : _onQueryChanged,
        ),
        if (_results.isNotEmpty) ...[
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
              itemCount: _results.length.clamp(0, 8),
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: DunesColors.borderSoft),
              itemBuilder: (context, index) {
                final row = _results[index];
                final code = (row['code'] ?? '').toString();
                final title = (row['title'] ?? row['name'] ?? '').toString();
                final label = code.isNotEmpty && title.isNotEmpty
                    ? '$code · $title'
                    : (code.isNotEmpty ? code : title);
                return ListTile(
                  dense: true,
                  title: Text(
                    label,
                    style: DunesTypography.sans(fontSize: 12),
                  ),
                  onTap: () => _selectProposal(row),
                );
              },
            ),
          ),
        ] else if (_searched && !_loading && hasText) ...[
          const SizedBox(height: 6),
          Text(
            '无匹配提案',
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ],
    );
  }
}

/// 通用远程搜索：行为完全由 [XflowRemoteSearchConfig] 驱动，无业务硬编码。
class _XflowRemoteSearchPicker extends StatefulWidget {
  const _XflowRemoteSearchPicker({
    required this.service,
    required this.config,
    required this.fieldKey,
    required this.value,
    required this.placeholder,
    required this.readonly,
    required this.onFieldChanged,
    this.scopeValues,
    this.onPatch,
  });

  final XflowService? service;
  final XflowRemoteSearchConfig config;
  final String fieldKey;
  final dynamic value;
  final String placeholder;
  final bool readonly;
  final XflowFieldChanged onFieldChanged;

  /// 分组作用域：fill 展示与回填都读/写这张 map，不写顶层 form。
  final Map<String, dynamic>? scopeValues;
  final void Function(Map<String, dynamic> patch)? onPatch;

  @override
  State<_XflowRemoteSearchPicker> createState() =>
      _XflowRemoteSearchPickerState();
}

class _XflowRemoteSearchPickerState extends State<_XflowRemoteSearchPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;
  bool _fromFill = false;

  XflowRemoteSearchConfig get _cfg => widget.config;

  bool get _useFillDisplay =>
      widget.scopeValues != null && _cfg.fill.length > 1;

  @override
  void initState() {
    super.initState();
    _fromFill =
        _useFillDisplay && _cfg.fillDisplayOf(widget.scopeValues).isNotEmpty;
    _controller.text = _resolvedDisplay();
  }

  @override
  void didUpdateWidget(covariant _XflowRemoteSearchPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useFillDisplay) {
      final next = _resolvedDisplay();
      if (!_focus.hasFocus && _controller.text != next) {
        _controller.text = next;
      }
      return;
    }
    if (oldWidget.value != widget.value) {
      final next = _displayText(widget.value);
      // 仅在外部写入（回填/导入）且输入框未聚焦时同步，避免打断手输。
      if (!_focus.hasFocus && _controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _resolvedDisplay() {
    if (_useFillDisplay && _fromFill) {
      final joined = _cfg.fillDisplayOf(widget.scopeValues);
      if (joined.isNotEmpty) return joined;
    }
    return _displayText(widget.value);
  }

  String _displayText(dynamic val) {
    if (val == null) return '';
    return val.toString();
  }

  String _errorMessage(Object e) {
    final raw = e.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length).trim();
    }
    return raw.trim().isEmpty ? '搜索失败' : raw.trim();
  }

  void _writeMany(Map<String, dynamic> patch) {
    final onPatch = widget.onPatch;
    if (onPatch != null) {
      onPatch(patch);
      return;
    }
    for (final entry in patch.entries) {
      widget.onFieldChanged(entry.key, entry.value);
    }
  }

  void _clearSelection() {
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _results = const [];
      _searched = false;
      _loading = false;
      _fromFill = false;
    });
    if (widget.onPatch != null) {
      final patch = <String, dynamic>{widget.fieldKey: ''};
      for (final key in _cfg.fill.keys) {
        patch[key] = '';
      }
      widget.onPatch!(patch);
      return;
    }
    widget.onFieldChanged(widget.fieldKey, '');
  }

  void _selectRow(Map<String, dynamic> row) {
    final patch = <String, dynamic>{};
    final value = _cfg.valueOf(row);
    if (value != null) {
      patch[widget.fieldKey] = value;
    }
    patch.addAll(_cfg.fillPatches(row));
    _fromFill = _useFillDisplay;
    if (_fromFill) {
      final merged = <String, dynamic>{
        ...?widget.scopeValues,
        ...patch,
      };
      _controller.text = _cfg.fillDisplayOf(merged);
    } else if (patch.containsKey(widget.fieldKey)) {
      _controller.text = '${patch[widget.fieldKey]}';
    }
    _writeMany(patch);
    setState(() {
      _results = const [];
      _searched = false;
      _loading = false;
    });
    _focus.unfocus();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (widget.service == null || query.length < _cfg.minChars) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await widget.service!.searchRemote(
        path: _cfg.path,
        queryParam: _cfg.queryParam,
        query: query,
      );
      if (!mounted || _controller.text.trim() != query) return;
      setState(() {
        _results = rows;
        _searched = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _searched = true;
        _results = const [];
      });
      showDunesToast(
        context,
        _errorMessage(e),
        kind: DunesToastKind.error,
      );
    }
  }

  void _onQueryChanged(String q) {
    _fromFill = false;
    if (!widget.readonly && _cfg.allowManual) {
      if (widget.onPatch != null) {
        widget.onPatch!({widget.fieldKey: q});
      } else {
        widget.onFieldChanged(widget.fieldKey, q);
      }
    }
    _debounce?.cancel();
    final wait = Duration(milliseconds: _cfg.debounceMs);
    _debounce = Timer(wait, () {
      if (!mounted) return;
      if (_controller.text.trim() == q.trim()) _search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          readOnly: widget.readonly,
          enableInteractiveSelection: true,
          contextMenuBuilder: (context, editableTextState) {
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          },
          decoration: xfInputDecoration(hint: widget.placeholder).copyWith(
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hasText && !widget.readonly
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                    onPressed: _clearSelection,
                    tooltip: '清除',
                  )
                : const Icon(
                    Icons.search,
                    size: 18,
                    color: DunesColors.text3,
                  ),
          ),
          style: xfInputTextStyle(),
          onChanged: widget.readonly ? null : _onQueryChanged,
        ),
        if (_results.isNotEmpty) ...[
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
              itemCount: _results.length.clamp(0, 12),
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: DunesColors.borderSoft),
              itemBuilder: (context, index) {
                final row = _results[index];
                final label = _cfg.labelOf(row);
                return ListTile(
                  dense: true,
                  title: Text(
                    label.isEmpty ? '（无标题）' : label,
                    style: DunesTypography.sans(fontSize: 12),
                  ),
                  onTap: () => _selectRow(row),
                );
              },
            ),
          ),
        ] else if (_searched && !_loading && hasText) ...[
          const SizedBox(height: 6),
          Text(
            '无匹配结果',
            style: DunesTypography.sans(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ],
    );
  }
}

extension on Iterable<XflowField> {
  XflowField? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}

class _XflowTagInput extends StatefulWidget {
  const _XflowTagInput({super.key, required this.hint, required this.onSubmit});

  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  State<_XflowTagInput> createState() => _XflowTagInputState();
}

class _XflowTagInputState extends State<_XflowTagInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? raw]) {
    final text = (raw ?? _controller.text).trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: xfInputTextStyle(),
      textInputAction: TextInputAction.done,
      decoration: xfInputDecoration(hint: widget.hint),
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onSubmitted: _submit,
      onChanged: (text) {
        if (text.contains(',') || text.contains('，')) {
          final parts = text.split(RegExp('[,，]'));
          for (var i = 0; i < parts.length - 1; i++) {
            _submit(parts[i]);
          }
          _controller.text = parts.last;
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
        }
      },
    );
  }
}
