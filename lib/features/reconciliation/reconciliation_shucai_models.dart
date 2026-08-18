/// 数财一体标签二 / 标签三的只读快照（资管 listResult 口径）。
class ShucaiSnapshot {
  const ShucaiSnapshot({
    required this.asOfDate,
    required this.tag2,
    required this.tag3,
    this.tag2Markdown = '',
    this.tag3Markdown = const {},
  });

  final String asOfDate;
  final ShucaiReport tag2;
  final Map<String, ShucaiReport> tag3;
  final String tag2Markdown;
  final Map<String, String> tag3Markdown;

  static const tag3TabOrder = <String>[
    'energy',
    'operator',
    'starCall',
    'goodCarOwner',
    'travelGold',
    'MY',
  ];

  static String tabLabel(String tab) {
    switch (tab) {
      case 'energy':
        return '能源';
      case 'operator':
        return '运营商';
      case 'starCall':
        return '明星来电';
      case 'goodCarOwner':
        return '好车主';
      case 'travelGold':
        return '出行金';
      case 'MY':
        return '民营';
      default:
        return tab;
    }
  }

  factory ShucaiSnapshot.fromJson(Map<String, dynamic> json) {
    final tag3Raw = json['tag3'];
    final tag3 = <String, ShucaiReport>{};
    if (tag3Raw is Map) {
      for (final entry in tag3Raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          tag3[key] = ShucaiReport.fromJson(
            Map<String, dynamic>.from(value),
          ).withTab(key);
        }
      }
    }
    final tag2Raw = json['tag2'];
    final tag3MdRaw = json['tag3Markdown'];
    final tag3Markdown = <String, String>{};
    if (tag3MdRaw is Map) {
      for (final entry in tag3MdRaw.entries) {
        final value = entry.value;
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isNotEmpty) tag3Markdown[entry.key.toString()] = text;
      }
    }
    final tag3Tables = json['tag3Tables'];
    if (tag3Tables is Map) {
      for (final entry in tag3Tables.entries) {
        final key = entry.key.toString();
        if ((tag3Markdown[key] ?? '').trim().isNotEmpty) continue;
        final built = shucaiMarkdownFromDisplayTable(entry.value);
        if (built.isNotEmpty) tag3Markdown[key] = built;
      }
    }
    var tag2Markdown = (json['tag2Markdown'] ?? '').toString();
    if (tag2Markdown.trim().isEmpty) {
      tag2Markdown = shucaiMarkdownFromDisplayTable(json['tag2Table']);
    }
    var tag2 = tag2Raw is Map
        ? ShucaiReport.fromJson(Map<String, dynamic>.from(tag2Raw))
        : const ShucaiReport(columns: [], rows: []);
    if (tag2.rows.isEmpty) {
      final fromTable = shucaiReportFromDisplayTable(
        json['tag2Table'],
        tab: 'tag2',
      );
      if (fromTable.rows.isNotEmpty) tag2 = fromTable;
    }
    if (tag3Tables is Map) {
      for (final entry in tag3Tables.entries) {
        final key = entry.key.toString();
        final existing = tag3[key];
        if (existing != null && existing.rows.isNotEmpty) continue;
        final fromTable = shucaiReportFromDisplayTable(
          entry.value,
          tab: key,
          keysFrom: existing,
        );
        if (fromTable.rows.isNotEmpty) tag3[key] = fromTable;
      }
    }
    return ShucaiSnapshot(
      asOfDate: (json['asOfDate'] ?? '').toString(),
      tag2: tag2,
      tag3: tag3,
      tag2Markdown: tag2Markdown,
      tag3Markdown: tag3Markdown,
    );
  }
}

String shucaiMarkdownFromDisplayTable(dynamic raw) {
  if (raw is! Map) return '';
  final title = (raw['title'] ?? '').toString().trim();
  final cols = (raw['columns'] is List)
      ? (raw['columns'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  if (cols.isEmpty) return '';
  final buf = StringBuffer();
  if (title.isNotEmpty) {
    buf.writeln('## $title');
    buf.writeln();
  }
  buf.writeln('| ${cols.join(' | ')} |');
  buf.writeln('| ${List.filled(cols.length, '---').join(' | ')} |');
  final rows = raw['rows'];
  if (rows is List) {
    for (final row in rows) {
      if (row is! List) continue;
      final cells = [
        for (var i = 0; i < cols.length; i++)
          i < row.length ? row[i].toString() : '',
      ];
      buf.writeln('| ${cells.join(' | ')} |');
    }
  }
  return buf.toString();
}

ShucaiReport shucaiReportFromDisplayTable(
  dynamic raw, {
  String tab = '',
  ShucaiReport? keysFrom,
}) {
  if (raw is! Map) return keysFrom ?? const ShucaiReport(columns: [], rows: []);
  final colLabels = (raw['columns'] is List)
      ? (raw['columns'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  if (colLabels.isEmpty) {
    return keysFrom ?? const ShucaiReport(columns: [], rows: []);
  }
  final columns = [
    for (var i = 0; i < colLabels.length; i++)
      ShucaiColumn(
        field: 'c$i',
        label: colLabels[i],
        text: i == 0,
      ),
  ];
  final rows = <Map<String, dynamic>>[];
  final rawRows = raw['rows'];
  if (rawRows is List) {
    for (var r = 0; r < rawRows.length; r++) {
      final item = rawRows[r];
      if (item is! List) continue;
      final map = <String, dynamic>{};
      for (var c = 0; c < columns.length; c++) {
        map[columns[c].field] = c < item.length ? item[c].toString() : '';
      }
      final keyRow = (keysFrom != null && r < keysFrom.rows.length)
          ? keysFrom.rows[r]
          : null;
      if (keyRow != null) {
        for (final entry in keyRow.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }
      } else {
        final name = (map['c0'] ?? '').toString().trim();
        if (name == '合计' || name.endsWith('合计') || name.contains('总计')) {
          map['rowType'] = 'TOTAL';
          map['rowKey'] = '__TOTAL__';
          map['detailName'] = '合计';
        } else if (name.isNotEmpty) {
          map['rowKey'] = name;
          map['detailName'] = name;
        }
      }
      rows.add(map);
    }
  }
  if (rows.isEmpty) {
    return keysFrom ?? ShucaiReport(columns: columns, rows: const [], tab: tab);
  }
  return ShucaiReport(columns: columns, rows: rows, tab: tab);
}

class ShucaiColumn {
  const ShucaiColumn({
    required this.field,
    required this.label,
    this.tip = '',
    this.text = false,
  });

  final String field;
  final String label;
  final String tip;
  final bool text;

  factory ShucaiColumn.fromJson(Map<String, dynamic> json) {
    final field = (json['field'] ?? json['fieldKey'] ?? '').toString().trim();
    return ShucaiColumn(
      field: field,
      label: (json['label'] ?? field).toString(),
      tip: (json['tip'] ?? '').toString(),
      text: json['text'] == true || _shucaiFieldLooksLikeName(field, (json['label'] ?? field).toString()),
    );
  }
}

bool _shucaiFieldLooksLikeName(String field, String label) {
  final f = field.toLowerCase();
  return f.contains('name') ||
      f.contains('project') ||
      label.contains('名称') ||
      label.contains('主体') ||
      label.contains('省份') ||
      label.contains('项目');
}

bool shucaiIsNameColumn(ShucaiColumn col) {
  return col.text || _shucaiFieldLooksLikeName(col.field, col.label);
}

class ShucaiReport {
  const ShucaiReport({required this.columns, required this.rows, this.tab = ''});

  final List<ShucaiColumn> columns;
  final List<Map<String, dynamic>> rows;
  final String tab;

  factory ShucaiReport.fromJson(Map<String, dynamic> json) {
    final cols = <ShucaiColumn>[];
    final rawCols = json['columns'];
    if (rawCols is List) {
      for (final item in rawCols) {
        if (item is Map) {
          cols.add(ShucaiColumn.fromJson(Map<String, dynamic>.from(item)));
        } else if (item != null) {
          final label = item.toString();
          cols.add(
            ShucaiColumn(
              field: 'c${cols.length}',
              label: label,
              text: cols.isEmpty,
            ),
          );
        }
      }
    }
    final rows = <Map<String, dynamic>>[];
    final rawRows = json['rows'];
    if (rawRows is List) {
      for (var i = 0; i < rawRows.length; i++) {
        final item = rawRows[i];
        if (item is Map) {
          rows.add(Map<String, dynamic>.from(item));
          continue;
        }
        if (item is! List || cols.isEmpty) continue;
        final map = <String, dynamic>{};
        for (var c = 0; c < cols.length; c++) {
          map[cols[c].field] = c < item.length ? item[c].toString() : '';
        }
        final name = (map[cols.first.field] ?? '').toString().trim();
        if (name == '合计' || name.endsWith('合计')) {
          map['rowType'] = 'TOTAL';
          map['rowKey'] = '__TOTAL__';
          map['detailName'] = '合计';
        }
        rows.add(map);
      }
    }
    return ShucaiReport(
      columns: cols,
      rows: rows,
      tab: (json['tab'] ?? '').toString(),
    );
  }

  ShucaiReport copyWith({
    List<ShucaiColumn>? columns,
    List<Map<String, dynamic>>? rows,
    String? tab,
  }) {
    return ShucaiReport(
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      tab: tab ?? this.tab,
    );
  }

  ShucaiReport withTab(String value) {
    final t = value.trim();
    if (t.isEmpty || tab.trim() == t) return this;
    return copyWith(tab: t);
  }

  /// 标签二 columns 不含省份列，展示时补到最左侧。
  ShucaiReport get withProvinceColumn {
    final hasName = columns.any(
      (c) =>
          c.field == 'provinceName' ||
          c.field == 'groupName' ||
          c.label == '省份',
    );
    if (hasName) return this;
    return ShucaiReport(
      columns: [
        const ShucaiColumn(field: 'provinceName', label: '省份'),
        ...columns,
      ],
      rows: rows,
      tab: tab,
    );
  }

  int get detailRowCount =>
      rows.where((r) => !shucaiIsSummaryRow(r)).length;

  Map<String, dynamic>? get totalRow {
    for (final row in rows) {
      final type = (row['rowType'] ?? '').toString().toUpperCase();
      final key = (row['rowKey'] ?? '').toString();
      if (type == 'TOTAL' || key == '__TOTAL__') return row;
    }
    return null;
  }

  /// 同组后续行若项目名为空，用上一行的项目名补上（不合并单元格）。
  ShucaiReport get withFilledGroupNames {
    if (rows.isEmpty || columns.isEmpty) return this;
    final firstField = columns.first.field;
    var lastName = '';
    final filled = <Map<String, dynamic>>[];
    for (final row in rows) {
      final copy = Map<String, dynamic>.from(row);
      final type = (copy['rowType'] ?? '').toString().toUpperCase();
      final isGrandTotal =
          type == 'TOTAL' || (copy['rowKey'] ?? '').toString() == '__TOTAL__';
      final name = (copy['groupName'] ??
              copy['groupKey'] ??
              copy[firstField] ??
              '')
          .toString()
          .trim();
      if (isGrandTotal) {
        filled.add(copy);
        lastName = '';
        continue;
      }
      if (name.isNotEmpty) {
        lastName = name;
      } else if (lastName.isNotEmpty) {
        copy['groupName'] = lastName;
        copy['groupKey'] ??= lastName;
        if ((copy[firstField] ?? '').toString().trim().isEmpty) {
          copy[firstField] = lastName;
        }
      }
      filled.add(copy);
    }
    return ShucaiReport(columns: columns, rows: filled, tab: tab);
  }

  /// 没有整表合计时补一行，对明细数字列求和。
  ShucaiReport get withEnsuredGrandTotal {
    if (rows.isEmpty || columns.isEmpty || totalRow != null) return this;
    final last = rows.last;
    final lastType = (last['rowType'] ?? '').toString().toUpperCase();
    if (lastType != 'GROUP_TOTAL' && shucaiIsSummaryRow(last)) return this;
    final sources = rows.where((r) {
      final type = (r['rowType'] ?? '').toString().toUpperCase();
      if (type == 'DETAIL' || type.isEmpty) {
        return !shucaiIsSummaryRow(r);
      }
      return false;
    }).toList();
    final toSum = sources.isNotEmpty
        ? sources
        : rows.where((r) => !shucaiIsSummaryRow(r)).toList();
    if (toSum.isEmpty) return this;

    var nameIdx = columns.indexWhere(
      (c) =>
          c.label.contains('项目') ||
          c.field == 'detailName' ||
          c.field == 'projectName',
    );
    if (nameIdx < 0) {
      nameIdx = columns.indexWhere(shucaiIsNameColumn);
    }
    if (nameIdx < 0) nameIdx = 0;

    final total = <String, dynamic>{
      'rowType': 'TOTAL',
      'rowKey': '__TOTAL__',
      'isTotal': true,
      'groupKey': '__TOTAL__',
      'groupName': '合计',
      'detailName': '合计',
    };
    for (var i = 0; i < columns.length; i++) {
      final col = columns[i];
      if (shucaiIsNameColumn(col) || col.text) {
        total[col.field] = i == nameIdx ? '合计' : '';
        continue;
      }
      var sum = 0.0;
      var hit = false;
      for (final row in toSum) {
        final amount = shucaiCellAmount(shucaiCellRaw(row, col));
        if (amount == null) continue;
        sum += amount;
        hit = true;
      }
      total[col.field] = hit ? sum : '';
    }
    return ShucaiReport(
      columns: columns,
      rows: [...rows, total],
      tab: tab,
    );
  }

  ShucaiColumn? columnByLabel(String label) {
    for (final col in columns) {
      if (col.label == label) return col;
    }
    return null;
  }
}

dynamic shucaiCellRaw(Map<String, dynamic> row, ShucaiColumn col) {
  return row[col.field];
}

double? shucaiCellAmount(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final clean = raw.replaceAll(',', '').replaceAll('%', '').trim();
    if (clean.isEmpty || clean == '-' || clean == '—') return null;
    return double.tryParse(clean);
  }
  if (raw is Map) {
    for (final key in const ['totalAmount', 'amount', 'value']) {
      final nested = shucaiCellAmount(raw[key]);
      if (nested != null) return nested;
    }
  }
  return null;
}

String shucaiCellText(dynamic raw, {required bool preferText}) {
  if (raw == null) return '—';
  if (raw is Map) {
    if (preferText) {
      final text = (raw['textValue'] ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    final amount = shucaiCellAmount(raw);
    if (amount != null) return formatShucaiAmount(amount);
    return '—';
  }
  if (raw is num) return formatShucaiAmount(raw.toDouble());
  final text = raw.toString().trim();
  if (text.isEmpty || text == 'null') return '—';
  return text;
}

/// 嵌套金额单元格的悬停说明：系统 / 人工 / 合计。
String shucaiNestedAmountTooltip(dynamic raw) {
  if (raw is! Map) return '';
  final system = shucaiCellAmount(raw['systemAmount']);
  final manual = shucaiCellAmount(raw['manualAmount']);
  if (system == null && manual == null) return '';
  final total =
      shucaiCellAmount(raw['totalAmount']) ?? shucaiCellAmount(raw);
  final parts = <String>[];
  if (system != null) parts.add('系统 ${formatShucaiAmount(system)}');
  if (manual != null) parts.add('人工 ${formatShucaiAmount(manual)}');
  if (total != null) parts.add('合计 ${formatShucaiAmount(total)}');
  return parts.join('\n');
}

bool shucaiIsSummaryRow(Map<String, dynamic> row) {
  if (row['isTotal'] == true) return true;
  final type = (row['rowType'] ?? '').toString().toUpperCase();
  final key = (row['rowKey'] ?? '').toString();
  final detail = (row['detailName'] ?? '').toString().trim();
  return type == 'TOTAL' ||
      type == 'GROUP_TOTAL' ||
      key == '__TOTAL__' ||
      detail == '合计';
}

bool shucaiIsGrandTotalRow(Map<String, dynamic> row) {
  final type = (row['rowType'] ?? '').toString().toUpperCase();
  return type == 'TOTAL' || (row['rowKey'] ?? '').toString() == '__TOTAL__';
}

bool shucaiIsGroupTotalRow(Map<String, dynamic> row) {
  return (row['rowType'] ?? '').toString().toUpperCase() == 'GROUP_TOTAL';
}

String shucaiGroupKeyOf(Map<String, dynamic> row) {
  return (row['groupKey'] ?? row['groupName'] ?? '').toString().trim();
}

enum ShucaiGroupMerge { none, fromGroupTotal, consecutive }

/// 标签三第 0 列合并：运营商/民营从 GROUP_TOTAL 起；能源/出行金/明星来电/好车主按连续 groupKey。
ShucaiGroupMerge shucaiGroupMergeMode(ShucaiReport report) {
  switch (report.tab.trim()) {
    case 'tag2':
      return ShucaiGroupMerge.none;
    case 'operator':
    case 'MY':
      return ShucaiGroupMerge.fromGroupTotal;
    case 'energy':
    case 'travelGold':
    case 'starCall':
    case 'goodCarOwner':
      return ShucaiGroupMerge.consecutive;
    default:
      if (report.rows.any(shucaiIsGroupTotalRow)) {
        return ShucaiGroupMerge.fromGroupTotal;
      }
      if (report.columns.isNotEmpty &&
          report.columns.first.field == 'groupName') {
        return ShucaiGroupMerge.consecutive;
      }
      return ShucaiGroupMerge.none;
  }
}

bool shucaiMergeTrailingMoneyColumns(
  ShucaiReport report,
  Map<String, dynamic> row,
) {
  switch (report.tab.trim()) {
    case 'travelGold':
      return true;
    case 'operator':
      final g = '${row['groupKey'] ?? ''}${row['groupName'] ?? ''}';
      return g.contains('出行');
    default:
      return false;
  }
}

bool shucaiIsTrailingMoneyColumn(ShucaiReport report, int colIndex) {
  if (report.columns.length < 2) return false;
  final last = report.columns.length - 1;
  if (colIndex != last && colIndex != last - 1) return false;
  final field = report.columns[colIndex].field;
  return field == 'monthPaid' || field == 'monthReceivableDiff';
}

bool _sameGroupAsPrevious(ShucaiReport report, int rowIndex) {
  if (rowIndex <= 0 || rowIndex >= report.rows.length) return false;
  final row = report.rows[rowIndex];
  final prev = report.rows[rowIndex - 1];
  if (shucaiIsGrandTotalRow(row) || shucaiIsGrandTotalRow(prev)) return false;
  final key = shucaiGroupKeyOf(row);
  return key.isNotEmpty && key == shucaiGroupKeyOf(prev);
}

/// 合并区域内后续行该格留空（不是 `-`），对齐资管 Markdown / rowspan。
bool shucaiMergedBlank(ShucaiReport report, int rowIndex, int colIndex) {
  if (rowIndex < 0 ||
      rowIndex >= report.rows.length ||
      colIndex < 0 ||
      colIndex >= report.columns.length) {
    return false;
  }
  final row = report.rows[rowIndex];
  if (shucaiIsGrandTotalRow(row)) return false;
  final mode = shucaiGroupMergeMode(report);
  if (colIndex == 0 && mode != ShucaiGroupMerge.none) {
    if (mode == ShucaiGroupMerge.fromGroupTotal) {
      return !shucaiIsGroupTotalRow(row);
    }
    return _sameGroupAsPrevious(report, rowIndex);
  }
  if (shucaiIsTrailingMoneyColumn(report, colIndex) &&
      shucaiMergeTrailingMoneyColumns(report, row)) {
    if (mode == ShucaiGroupMerge.fromGroupTotal) {
      return !shucaiIsGroupTotalRow(row);
    }
    return _sameGroupAsPrevious(report, rowIndex);
  }
  return false;
}

List<String> shucaiActionableRowKeys(ShucaiReport report) {
  return [
    for (var i = 0; i < report.rows.length; i++)
      if (!shucaiIsSummaryRow(report.rows[i])) shucaiRowKey(report.rows[i], i),
  ];
}

String shucaiRowDisplayName(Map<String, dynamic> row) {
  final group = (row['groupName'] ?? row['groupKey'] ?? '').toString().trim();
  var detail = (row['detailName'] ?? '').toString().trim();
  if (detail.isEmpty) {
    detail = (row['provinceName'] ?? '').toString().trim();
  }
  final third = (row['thirdName'] ?? '').toString().trim();
  final parts = <String>[
    if (group.isNotEmpty) group,
    if (detail.isNotEmpty && detail != group) detail,
    if (third.isNotEmpty) third,
  ];
  if (parts.isEmpty) return '未命名明细';
  return parts.join(' · ');
}

String shucaiRowKey(Map<String, dynamic> row, int index) {
  final key = (row['rowKey'] ?? '').toString().trim();
  if (key.isNotEmpty && key != '__TOTAL__') return key;
  final group = (row['groupKey'] ?? row['groupName'] ?? '').toString().trim();
  var detail = (row['detailName'] ?? '').toString().trim();
  if (detail.isEmpty) {
    detail = (row['provinceName'] ?? '').toString().trim();
  }
  final third = (row['thirdName'] ?? '').toString().trim();
  return 'idx:$index|$group|$detail|$third';
}

String reconRowDecisionId(String tab, String rowKey) => '$tab|$rowKey';

const reconChainL1 = 'L1';
const reconChainFinance = 'FINANCE';
const reconChainL2 = 'L2';

const reconAuditChainSteps = <String>[
  reconChainL1,
  reconChainFinance,
  reconChainL2,
];

String reconChainStepFromRole(String role, {String roleLabel = ''}) {
  final u = role.toUpperCase().trim();
  if (u == 'L1' || u.endsWith('_L1')) return reconChainL1;
  if (u == 'FINANCE' || u.endsWith('_FINANCE')) return reconChainFinance;
  if (u == 'L2' || u.endsWith('_L2')) return reconChainL2;
  final label = roleLabel.trim();
  if (label.contains('一层')) return reconChainL1;
  if (label.contains('财务')) return reconChainFinance;
  if (label.contains('二层')) return reconChainL2;
  return '';
}

String reconChainStepLabel(String step) {
  switch (step.toUpperCase().trim()) {
    case reconChainL1:
      return '一层';
    case reconChainFinance:
      return '财务';
    case reconChainL2:
      return '二层';
    default:
      return step.trim().isEmpty ? '审核' : step.trim();
  }
}

bool reconRoleIsL1(String role) =>
    reconChainStepFromRole(role) == reconChainL1;

bool reconRoleIsFinance(String role) =>
    reconChainStepFromRole(role) == reconChainFinance;

/// 一层只看一层；财务看一层+财务；二层/最终人看三层。
List<String> reconVisibleAuditSteps(String myRole) {
  switch (reconChainStepFromRole(myRole)) {
    case reconChainL1:
      return const [reconChainL1];
    case reconChainFinance:
      return const [reconChainL1, reconChainFinance];
    default:
      return reconAuditChainSteps;
  }
}

List<ReconRowReviewer> reconFilterReviewersForSteps(
  List<ReconRowReviewer> reviewers,
  List<String> steps,
) {
  if (steps.isEmpty) return const [];
  final allow = steps.toSet();
  return [
    for (final item in reviewers)
      if (allow.contains(item.chainStepKey)) item,
  ];
}

class ReconRowReviewer {
  const ReconRowReviewer({
    required this.userName,
    this.tab = '',
    this.rowKey = '',
    this.role = '',
    this.roleLabel = '上一层',
    this.chainStep = '',
    this.decision = '',
    this.reason = '',
    this.rejectReason = '',
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.decidedAt = '',
    this.userId = 0,
  });

  final String tab;
  final String rowKey;
  final String userName;
  final String role;
  final String roleLabel;
  final String chainStep;
  final String decision;
  final String reason;
  final String rejectReason;
  final String avatarPreset;
  final String avatarObjectKey;
  final String decidedAt;
  final int userId;

  bool get confirmed =>
      decision.toUpperCase() == 'CONFIRM' ||
      decision.toUpperCase() == 'RECONFIRM';
  bool get reconfirmed => decision.toUpperCase() == 'RECONFIRM';
  bool get rejected => decision.toUpperCase() == 'REJECT';

  String get chainStepKey {
    final fromField = chainStep.toUpperCase().trim();
    if (fromField == reconChainL1 ||
        fromField == reconChainFinance ||
        fromField == reconChainL2) {
      return fromField;
    }
    return reconChainStepFromRole(role, roleLabel: roleLabel);
  }

  String get statusLabel {
    if (rejected) return '已驳回';
    if (reconfirmed) return '已复核';
    if (confirmed) return '已确认';
    return '未处理';
  }

  factory ReconRowReviewer.fromJson(Map<String, dynamic> json) {
    final role = (json['role'] ?? '').toString();
    final roleLabel = (json['roleLabel'] ?? '').toString();
    final chainStep = (json['chainStep'] ?? '').toString();
    final resolvedLabel = roleLabel.trim().isNotEmpty
        ? roleLabel.trim()
        : (role.trim().isNotEmpty
              ? reconChainStepLabel(reconChainStepFromRole(role))
              : '上一层');
    return ReconRowReviewer(
      tab: (json['tab'] ?? '').toString(),
      rowKey: (json['rowKey'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      role: role,
      roleLabel: resolvedLabel,
      chainStep: chainStep,
      decision: (json['decision'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      rejectReason: (json['rejectReason'] ?? '').toString(),
      avatarPreset: (json['avatarPreset'] ?? '').toString(),
      avatarObjectKey: (json['avatarObjectKey'] ?? '').toString(),
      decidedAt: (json['decidedAt'] ?? '').toString(),
      userId: (json['userId'] as num?)?.toInt() ?? 0,
    );
  }
}

void reconIndexRowReviewer(
  Map<String, List<ReconRowReviewer>> previous,
  ReconRowReviewer reviewer,
) {
  final rowKey = reviewer.rowKey.trim();
  if (rowKey.isEmpty) return;
  void add(String key) {
    final list = previous.putIfAbsent(key, () => <ReconRowReviewer>[]);
    final step = reviewer.chainStepKey;
    final idx = step.isEmpty
        ? -1
        : list.indexWhere((item) => item.chainStepKey == step);
    if (idx >= 0) {
      list[idx] = reviewer;
    } else {
      list.add(reviewer);
    }
  }

  add(rowKey);
  final tab = reviewer.tab.trim();
  if (tab.isNotEmpty) add(reconRowDecisionId(tab, rowKey));
}

List<ReconRowReviewer> reconReviewersForRow({
  required Map<String, List<ReconRowReviewer>> previous,
  required String tab,
  required String rowKey,
}) {
  if (rowKey.trim().isEmpty) return const [];
  final keyed = previous[reconRowDecisionId(tab, rowKey)];
  if (keyed != null && keyed.isNotEmpty) return List<ReconRowReviewer>.from(keyed);
  final fallback = previous[rowKey];
  if (fallback == null || fallback.isEmpty) return const [];
  return List<ReconRowReviewer>.from(fallback);
}

ReconRowReviewer? reconReviewerForLayer(
  List<ReconRowReviewer> reviewers,
  String step,
) {
  final want = step.toUpperCase().trim();
  for (final item in reviewers) {
    if (item.chainStepKey == want) return item;
  }
  return null;
}

ReconRowReviewer? reconLatestReviewer(List<ReconRowReviewer> reviewers) {
  for (final step in [reconChainL2, reconChainFinance, reconChainL1]) {
    final item = reconReviewerForLayer(reviewers, step);
    if (item != null) return item;
  }
  return reviewers.isEmpty ? null : reviewers.last;
}

ReconRowReviewer? reconReviewerForRow({
  required Map<String, List<ReconRowReviewer>> previous,
  required String tab,
  required String rowKey,
}) {
  return reconLatestReviewer(
    reconReviewersForRow(previous: previous, tab: tab, rowKey: rowKey),
  );
}

Map<String, List<ReconRowReviewer>> reconMergeMineReviewers({
  required Map<String, List<ReconRowReviewer>> previous,
  required Iterable<ReconRowDecision> mine,
  required String myRole,
  String userName = '',
  int userId = 0,
  String avatarPreset = '',
  String avatarObjectKey = '',
}) {
  final step = reconChainStepFromRole(myRole);
  if (step.isEmpty) return previous;
  final out = <String, List<ReconRowReviewer>>{
    for (final entry in previous.entries)
      entry.key: List<ReconRowReviewer>.from(entry.value),
  };
  for (final item in mine) {
    final rowKey = item.rowKey.trim();
    if (rowKey.isEmpty) continue;
    final existing = reconReviewersForRow(
      previous: out,
      tab: item.tab,
      rowKey: rowKey,
    );
    final current = reconReviewerForLayer(existing, step);
    if (current != null && current.userId != 0 && userId != 0 && current.userId != userId) {
      continue;
    }
    reconIndexRowReviewer(
      out,
      ReconRowReviewer(
        tab: item.tab,
        rowKey: rowKey,
        userName: userName.trim().isEmpty ? '我' : userName.trim(),
        role: myRole,
        roleLabel: reconChainStepLabel(step),
        chainStep: step,
        decision: item.decision,
        reason: item.reason,
        rejectReason: item.rejectReason,
        avatarPreset: avatarPreset.trim().isNotEmpty
            ? avatarPreset.trim()
            : (current?.avatarPreset ?? ''),
        avatarObjectKey: avatarObjectKey.trim().isNotEmpty
            ? avatarObjectKey.trim()
            : (current?.avatarObjectKey ?? ''),
        decidedAt: item.decidedAt,
        userId: userId,
      ),
    );
  }
  return out;
}

List<ReconRowReviewer> reconReviewersWithCardAcks({
  required List<ReconRowReviewer> reviewers,
  List<ReconPerson> acks = const [],
}) {
  if (reconReviewerForLayer(reviewers, reconChainL2) != null) {
    return reviewers;
  }
  ReconPerson? l2;
  for (final person in acks) {
    if (reconChainStepFromRole(person.role) == reconChainL2) {
      l2 = person;
      break;
    }
  }
  if (l2 == null) return reviewers;
  return [
    ...reviewers,
    ReconRowReviewer(
      userName: l2.displayName,
      role: l2.role,
      roleLabel: reconChainStepLabel(reconChainL2),
      chainStep: reconChainL2,
      decision: 'CONFIRM',
      avatarPreset: l2.avatarPreset,
      avatarObjectKey: l2.avatarObjectKey,
      decidedAt: l2.confirmedAt,
      userId: l2.userId,
    ),
  ];
}

String reconFormatDecidedAt(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日 ${two(local.hour)}:${two(local.minute)}';
}

({int total, int done, int rejected, int pending}) reconMineRowStats({
  required List<ShucaiReport> reports,
  required Map<String, ReconRowDecision> decisions,
}) {
  var total = 0;
  var done = 0;
  var rejected = 0;
  for (final report in reports) {
    for (var i = 0; i < report.rows.length; i++) {
      final row = report.rows[i];
      if (shucaiIsSummaryRow(row)) continue;
      total++;
      final key = shucaiRowKey(row, i);
      final mine = decisions[reconRowDecisionId(report.tab, key)] ??
          decisions[key];
      if (mine == null) continue;
      done++;
      if (mine.rejected) rejected++;
    }
  }
  final pending = total - done;
  return (
    total: total,
    done: done,
    rejected: rejected,
    pending: pending < 0 ? 0 : pending,
  );
}

({int total, int confirmed, int rejected, int pending}) reconReviewStats({
  required ShucaiReport report,
  required String tab,
  required Map<String, List<ReconRowReviewer>> previous,
}) {
  var total = 0;
  var confirmed = 0;
  var rejected = 0;
  for (var i = 0; i < report.rows.length; i++) {
    final row = report.rows[i];
    if (shucaiIsSummaryRow(row)) continue;
    total++;
    final reviewer = reconReviewerForRow(
      previous: previous,
      tab: tab,
      rowKey: shucaiRowKey(row, i),
    );
    if (reviewer == null) continue;
    if (reviewer.rejected) {
      rejected++;
    } else if (reviewer.confirmed) {
      confirmed++;
    }
  }
  final pending = total - confirmed - rejected;
  return (
    total: total,
    confirmed: confirmed,
    rejected: rejected,
    pending: pending < 0 ? 0 : pending,
  );
}

class ReconRowDecision {
  const ReconRowDecision({
    this.tab = '',
    required this.rowKey,
    required this.decision,
    this.reason = '',
    this.rejectReason = '',
    this.decidedAt = '',
  });

  final String tab;
  final String rowKey;
  final String decision;
  final String reason;
  final String rejectReason;
  final String decidedAt;

  bool get confirmed =>
      decision.toUpperCase() == 'CONFIRM' ||
      decision.toUpperCase() == 'RECONFIRM';
  bool get reconfirmed => decision.toUpperCase() == 'RECONFIRM';
  bool get rejected => decision.toUpperCase() == 'REJECT';
  String get id => reconRowDecisionId(tab, rowKey);

  Map<String, dynamic> toJson() => {
    'tab': tab,
    'rowKey': rowKey,
    'decision': decision,
    if (reason.trim().isNotEmpty) 'reason': reason.trim(),
  };

  factory ReconRowDecision.fromJson(Map<String, dynamic> json) {
    return ReconRowDecision(
      tab: (json['tab'] ?? '').toString(),
      rowKey: (json['rowKey'] ?? '').toString(),
      decision: (json['decision'] ?? '').toString().toUpperCase(),
      reason: (json['reason'] ?? '').toString(),
      rejectReason: (json['rejectReason'] ?? '').toString(),
      decidedAt: (json['decidedAt'] ?? '').toString(),
    );
  }
}

String formatShucaiAmount(double amount) {
  final sign = amount < 0 ? '-' : '';
  final abs = amount.abs();
  final isInt = abs == abs.roundToDouble();
  final digits = isInt ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  final parts = digits.split('.');
  final chars = parts[0].split('').reversed.toList();
  final buf = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) buf.write(',');
    buf.write(chars[i]);
  }
  final intPart = buf.toString().split('').reversed.join();
  if (parts.length == 1) return '$sign$intPart';
  return '$sign$intPart.${parts[1]}';
}

String formatShucaiCompact(double? amount) {
  if (amount == null) return '—';
  final sign = amount < 0 ? '-' : '';
  final wan = amount.abs() / 10000;
  if (wan >= 10000) return '$sign${(wan / 10000).toStringAsFixed(2)}亿';
  if (wan >= 1) {
    final digits = wan >= 100 ? 0 : 1;
    return '$sign${wan.toStringAsFixed(digits)}万';
  }
  return formatShucaiAmount(amount);
}

String shucaiDisplayDate(String asOfDate) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(asOfDate);
  if (m == null) return asOfDate;
  return '${m.group(1)}年${int.parse(m.group(2)!)}月${int.parse(m.group(3)!)}日';
}

String reconSectorFromCard(String cardType) {
  final raw = cardType.trim();
  if (raw.isEmpty) return '';
  switch (raw.toUpperCase()) {
    case 'CNPC':
    case 'TAG2':
      return 'CNPC';
    case 'ENERGY':
    case 'TAG3_ENERGY':
      return 'ENERGY';
    case 'PRIVATE':
    case 'MY':
      return 'PRIVATE';
    case 'OPERATOR':
    case 'TAG3_OPERATOR':
      return 'OPERATOR';
    case 'TRAVEL':
    case 'TRAVELGOLD':
      return 'TRAVEL';
    case 'L1':
    case 'FINANCE':
    case 'L2':
    case 'FINAL':
    case 'TAG2_FINANCE':
    case 'TAG3_FINANCE':
    case 'ENERGY_L1':
    case 'ENERGY_L2':
    case 'OPERATOR_L1':
    case 'OPERATOR_L2':
      return '';
  }
  if (raw.contains('出行金')) return 'TRAVEL';
  if (raw.contains('民营')) return 'PRIVATE';
  if (raw.contains('运营商')) return 'OPERATOR';
  if (raw.contains('中石油') || raw.contains('标签二') || raw.contains('各省资金')) {
    return 'CNPC';
  }
  if (raw.contains('能源')) return 'ENERGY';
  return '';
}

bool reconIsPushStep(String cardType) {
  switch (cardType.trim().toUpperCase()) {
    case 'L1':
    case 'FINANCE':
    case 'L2':
    case 'FINAL':
    case 'TAG2_FINANCE':
    case 'TAG3_FINANCE':
    case 'ENERGY_L1':
    case 'ENERGY_L2':
    case 'OPERATOR_L1':
    case 'OPERATOR_L2':
      return true;
    default:
      return false;
  }
}

String reconCardTitle(String cardType) {
  switch (cardType.toUpperCase()) {
    case 'CNPC':
    case 'TAG2':
      return '标签二-中石油';
    case 'TAG3_ENERGY':
    case 'ENERGY':
      return '标签三-能源';
    case 'TAG3_OPERATOR':
      return '标签三-运营商';
    case 'PRIVATE':
      return '标签三-民营';
    case 'OPERATOR':
      return '标签三-运营商';
    case 'TRAVEL':
      return '标签三-出行金';
    default:
      return cardType;
  }
}

const reconSectorTypes = <String>['CNPC', 'ENERGY', 'PRIVATE', 'OPERATOR', 'TRAVEL'];

/// 按板块取要渲染的表。CNPC 只用 tag2；能源/民营/运营商/出行金只用对应 tag3，不碰空 tag2。
List<(String title, String tab, ShucaiReport report)> shucaiReportsForSector(
  String cardType,
  ShucaiSnapshot snap,
) {
  (String, String, ShucaiReport)? pack(
    String title,
    String tab,
    ShucaiReport? report,
    String markdown,
  ) {
    final resolved = (report ?? const ShucaiReport(columns: [], rows: [])).withTab(tab);
    if (!shucaiReportHasContent(resolved, markdown)) return null;
    return (title, tab, resolved);
  }

  switch (reconSectorFromCard(cardType)) {
    case 'CNPC':
      final item = pack(
        '各省资金',
        'tag2',
        snap.tag2.withProvinceColumn,
        snap.tag2Markdown,
      );
      return [if (item != null) item];
    case 'ENERGY':
      final item = pack(
        '能源',
        'energy',
        snap.tag3['energy'],
        snap.tag3Markdown['energy'] ?? '',
      );
      return [if (item != null) item];
    case 'PRIVATE':
      final item = pack(
        '民营',
        'MY',
        snap.tag3['MY'],
        snap.tag3Markdown['MY'] ?? '',
      );
      return [if (item != null) item];
    case 'OPERATOR':
      final out = <(String title, String tab, ShucaiReport report)>[];
      for (final key in const ['operator', 'starCall', 'goodCarOwner']) {
        final item = pack(
          ShucaiSnapshot.tabLabel(key),
          key,
          snap.tag3[key],
          snap.tag3Markdown[key] ?? '',
        );
        if (item != null) out.add(item);
      }
      return out;
    case 'TRAVEL':
      final item = pack(
        '出行金',
        'travelGold',
        snap.tag3['travelGold'],
        snap.tag3Markdown['travelGold'] ?? '',
      );
      return [if (item != null) item];
    default:
      return const [];
  }
}

bool shucaiReportHasContent(ShucaiReport report, String markdown) {
  return report.rows.isNotEmpty || markdown.trim().isNotEmpty;
}

bool reconRoleIsL2(String role) {
  final u = role.toUpperCase();
  return u == 'L2' || u.endsWith('_L2');
}

bool reconRoleIsFinal(String role) => role.toUpperCase() == 'FINAL';

String reconAsOfDateFromText(String text) {
  final m = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(text);
  return m?.group(1) ?? '';
}

int reconRoleLayer(String role) {
  switch (role.toUpperCase()) {
    case 'TAG2_FINANCE':
    case 'TAG3_FINANCE':
      return 1;
    case 'ENERGY_L1':
    case 'OPERATOR_L1':
      return 2;
    case 'ENERGY_L2':
    case 'OPERATOR_L2':
      return 3;
    default:
      return 99;
  }
}

class ReconLayerProgress {
  const ReconLayerProgress({
    required this.layer,
    this.key = '',
    this.label = '',
    this.expectedCount = 0,
    this.confirmedCount = 0,
    this.complete = false,
  });

  final int layer;
  final String key;
  final String label;
  final int expectedCount;
  final int confirmedCount;
  final bool complete;

  factory ReconLayerProgress.fromJson(Map<String, dynamic> json) {
    return ReconLayerProgress(
      layer: (json['layer'] as num?)?.toInt() ?? 0,
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      complete: json['complete'] == true,
    );
  }
}

class ReconPerson {
  const ReconPerson({
    required this.userId,
    this.userName = '',
    this.role = '',
    this.comment = '',
    this.confirmedAt = '',
    this.avatarPreset = '',
    this.avatarObjectKey = '',
  });

  final int userId;
  final String userName;
  final String role;
  final String comment;
  final String confirmedAt;
  final String avatarPreset;
  final String avatarObjectKey;

  String get displayName => userName.trim().isEmpty ? '用户$userId' : userName.trim();

  String get roleLabel {
    switch (role.toUpperCase()) {
      case 'FINAL':
        return '最终人';
      case 'FINANCE':
      case 'TAG2_FINANCE':
        return '财务';
      case 'TAG3_FINANCE':
        return '财务';
      case 'L1':
      case 'ENERGY_L1':
        return '业务一层';
      case 'L2':
      case 'ENERGY_L2':
        return '业务二层';
      case 'OPERATOR_L1':
        return '业务一层';
      case 'OPERATOR_L2':
        return '业务二层';
      default:
        return role.isEmpty ? '核对人' : role;
    }
  }

  factory ReconPerson.fromJson(Map<String, dynamic> json) {
    return ReconPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: (json['userName'] ?? '').toString(),
      role: (json['role'] ?? json['myRole'] ?? '').toString(),
      comment: (json['comment'] ?? '').toString(),
      confirmedAt: (json['confirmedAt'] ?? '').toString(),
      avatarPreset: (json['avatarPreset'] ?? '').toString(),
      avatarObjectKey: (json['avatarObjectKey'] ?? '').toString(),
    );
  }
}

class ReconCardStatus {
  const ReconCardStatus({
    required this.cardType,
    required this.asOfDate,
    this.title = '',
    this.expected = const [],
    this.acks = const [],
    this.others = const [],
    this.mine,
    this.myRole = '',
    this.myLayer = 0,
    this.currentLayer = 0,
    this.waitingReason = '',
    this.layers = const [],
    this.canConfirm = true,
    this.expectedCount = 0,
    this.confirmedCount = 0,
  });

  final String cardType;
  final String asOfDate;
  final String title;
  final List<ReconPerson> expected;
  final List<ReconPerson> acks;
  final List<ReconPerson> others;
  final ReconPerson? mine;
  final String myRole;
  final int myLayer;
  final int currentLayer;
  final String waitingReason;
  final List<ReconLayerProgress> layers;
  final bool canConfirm;
  final int expectedCount;
  final int confirmedCount;

  bool get confirmed => mine != null && !reconRoleIsFinal(myRole);
  bool get viewerOnly => reconRoleIsFinal(myRole);
  bool get waitingPrevious => waitingReason.trim().isNotEmpty;

  factory ReconCardStatus.fromJson(Map<String, dynamic> json) {
    List<ReconPerson> parseList(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => ReconPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    ReconPerson? mine;
    final mineRaw = json['mine'];
    if (mineRaw is Map) {
      mine = ReconPerson.fromJson(Map<String, dynamic>.from(mineRaw));
    }
    final layersRaw = json['layers'];
    final layers = <ReconLayerProgress>[];
    if (layersRaw is List) {
      for (final item in layersRaw) {
        if (item is Map) {
          layers.add(
            ReconLayerProgress.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return ReconCardStatus(
      cardType: (json['cardType'] ?? '').toString(),
      asOfDate: (json['asOfDate'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      expected: parseList(json['expected']),
      acks: parseList(json['acks']),
      others: parseList(json['others']),
      mine: mine,
      myRole: (json['myRole'] ?? '').toString(),
      myLayer: (json['myLayer'] as num?)?.toInt() ?? reconRoleLayer((json['myRole'] ?? '').toString()),
      currentLayer: (json['currentLayer'] as num?)?.toInt() ?? 0,
      waitingReason: (json['waitingReason'] ?? '').toString(),
      layers: layers,
      canConfirm: json.containsKey('canConfirm')
          ? json['canConfirm'] == true
          : (json['myRole'] ?? '').toString().toUpperCase() != 'FINAL',
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReconOverviewMineChip {
  const ReconOverviewMineChip({required this.label, required this.done});

  final String label;
  final bool done;
}

/// 二级页「你已确认」：与详情页本人确认状态同一含义，不是整层人数。
ReconOverviewMineChip reconOverviewMineChip({
  ReconCardStatus? status,
  bool teamConfirmed = false,
}) {
  if (status == null) {
    return ReconOverviewMineChip(
      label: teamConfirmed ? '已确认' : '未确认',
      done: teamConfirmed,
    );
  }
  if (status.viewerOnly) {
    return const ReconOverviewMineChip(label: '仅查阅', done: false);
  }
  if (status.confirmed) {
    return const ReconOverviewMineChip(label: '你已确认', done: true);
  }
  if (status.waitingPrevious) {
    return const ReconOverviewMineChip(label: '待上一层', done: false);
  }
  return const ReconOverviewMineChip(label: '待你确认', done: false);
}

class ReconPeopleAckEntry {
  const ReconPeopleAckEntry({
    required this.person,
    required this.confirmed,
    this.decidedAt = '',
    this.step = '',
  });

  final ReconPerson person;
  final bool confirmed;
  final String decidedAt;
  final String step;
}

class ReconSectorPeopleAck {
  const ReconSectorPeopleAck({
    required this.sector,
    required this.title,
    this.people = const [],
  });

  final String sector;
  final String title;
  final List<ReconPeopleAckEntry> people;

  int get confirmedCount => people.where((e) => e.confirmed).length;
}

List<ReconPeopleAckEntry> reconPeopleAckEntries(ReconCardStatus? status) {
  if (status == null) return const [];
  final acked = <int, ReconPerson>{
    for (final person in status.acks) person.userId: person,
  };
  final seen = <int>{};
  final out = <ReconPeopleAckEntry>[];
  void add(ReconPerson person, {required bool confirmed, String decidedAt = ''}) {
    if (person.userId <= 0 || seen.contains(person.userId)) return;
    final step = reconChainStepFromRole(person.role);
    if (step.isEmpty) return;
    seen.add(person.userId);
    out.add(
      ReconPeopleAckEntry(
        person: person,
        confirmed: confirmed,
        decidedAt: decidedAt,
        step: step,
      ),
    );
  }

  for (final person in status.expected) {
    final ack = acked[person.userId];
    add(
      person,
      confirmed: ack != null,
      decidedAt: ack?.confirmedAt ?? '',
    );
  }
  for (final ack in status.acks) {
    add(ack, confirmed: true, decidedAt: ack.confirmedAt);
  }
  out.sort((a, b) {
    final ai = reconAuditChainSteps.indexOf(a.step);
    final bi = reconAuditChainSteps.indexOf(b.step);
    if (ai != bi) return ai.compareTo(bi);
    return a.person.displayName.compareTo(b.person.displayName);
  });
  return out;
}

List<ReconSectorPeopleAck> reconEveryonePeopleStatus(
  Map<String, ReconCardStatus> bySector,
) {
  return [
    for (final sector in reconSectorTypes)
      ReconSectorPeopleAck(
        sector: sector,
        title: reconCardTitle(sector),
        people: reconPeopleAckEntries(bySector[sector]),
      ),
  ];
}

class ReconStatusResponse {
  const ReconStatusResponse({
    required this.asOfDate,
    required this.visibleCards,
    required this.cards,
    this.isFinal = false,
  });

  final String asOfDate;
  final List<String> visibleCards;
  final List<ReconCardStatus> cards;
  final bool isFinal;

  ReconCardStatus? card(String cardType) {
    final want = reconSectorFromCard(cardType);
    final key = cardType.toUpperCase();
    for (final item in cards) {
      if (item.cardType.toUpperCase() == key) return item;
      if (want.isNotEmpty && reconSectorFromCard(item.cardType) == want) {
        return item;
      }
    }
    return null;
  }

  factory ReconStatusResponse.fromJson(Map<String, dynamic> json) {
    final cardsRaw = json['cards'];
    final cards = <ReconCardStatus>[];
    if (cardsRaw is List) {
      for (final item in cardsRaw) {
        if (item is Map) {
          cards.add(ReconCardStatus.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final visibleRaw = json['visibleCards'];
    return ReconStatusResponse(
      asOfDate: (json['asOfDate'] ?? '').toString(),
      visibleCards: visibleRaw is List
          ? visibleRaw.map((e) => e.toString()).toList(growable: false)
          : const [],
      isFinal: json['isFinal'] == true,
      cards: cards,
    );
  }
}

class ReconDateItem {
  const ReconDateItem({
    required this.asOfDate,
    this.expectedCount = 0,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.hasReject = false,
    this.pushedAt = '',
  });

  final String asOfDate;
  final int expectedCount;
  final int confirmedCount;
  final int pendingCount;
  final bool hasReject;
  final String pushedAt;

  bool get fullyConfirmed => expectedCount > 0 && pendingCount <= 0;

  factory ReconDateItem.fromJson(Map<String, dynamic> json) {
    return ReconDateItem(
      asOfDate: (json['asOfDate'] ?? '').toString(),
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      hasReject: json['hasReject'] == true,
      pushedAt: (json['pushedAt'] ?? '').toString(),
    );
  }
}

class ReconSectorOverview {
  const ReconSectorOverview({
    required this.sector,
    this.title = '',
    this.expectedCount = 0,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.layers = const [],
    this.unconfirmed = const [],
    this.notEntered = const [],
    this.hasReject = false,
    this.unmatched = const [],
  });

  final String sector;
  final String title;
  final int expectedCount;
  final int confirmedCount;
  final int pendingCount;
  final List<ReconLayerProgress> layers;
  final List<ReconPerson> unconfirmed;
  final List<ReconPerson> notEntered;
  final bool hasReject;
  final List<ReconUnmatchedSlot> unmatched;

  bool get fullyConfirmed => expectedCount > 0 && pendingCount <= 0;
  bool get hasUnmatched => unmatched.isNotEmpty;

  factory ReconSectorOverview.fromJson(Map<String, dynamic> json) {
    List<ReconPerson> people(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => ReconPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    List<ReconUnmatchedSlot> parseUnmatched(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => ReconUnmatchedSlot.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }

    final layersRaw = json['layers'];
    final layers = <ReconLayerProgress>[];
    if (layersRaw is List) {
      for (final item in layersRaw) {
        if (item is Map) {
          layers.add(
            ReconLayerProgress.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return ReconSectorOverview(
      sector: (json['sector'] ?? json['cardType'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      layers: layers,
      unconfirmed: people(json['unconfirmed']),
      notEntered: people(json['notEntered']),
      hasReject: json['hasReject'] == true,
      unmatched: parseUnmatched(json['unmatched']),
    );
  }
}

class ReconUnmatchedSlot {
  const ReconUnmatchedSlot({
    required this.step,
    this.name = '',
    this.reason = '',
    this.channel = '',
    this.province = '',
    this.projectName = '',
    this.count = 0,
  });

  final String step;
  final String name;
  final String reason;
  final String channel;
  final String province;
  final String projectName;
  final int count;

  bool get unmatched => reason == 'unmatched';
  bool get unassigned => reason == 'unassigned';

  String get location {
    return [
      channel,
      province,
      projectName,
    ].where((part) => part.trim().isNotEmpty).join(' · ');
  }

  String get stepLabel => reconChainStepLabel(step);

  factory ReconUnmatchedSlot.fromJson(Map<String, dynamic> json) {
    return ReconUnmatchedSlot(
      step: (json['step'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      channel: (json['channel'] ?? '').toString(),
      province: (json['province'] ?? '').toString(),
      projectName: (json['projectName'] ?? '').toString(),
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
