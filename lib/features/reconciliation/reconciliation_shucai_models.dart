/// 数财一体标签二 / 标签三的只读快照（资管 listResult 口径）。
class ShucaiSnapshot {
  const ShucaiSnapshot({
    required this.asOfDate,
    required this.tag2,
    required this.tag3,
  });

  final String asOfDate;
  final ShucaiReport tag2;
  final Map<String, ShucaiReport> tag3;

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
          tag3[key] = ShucaiReport.fromJson(Map<String, dynamic>.from(value));
        }
      }
    }
    final tag2Raw = json['tag2'];
    return ShucaiSnapshot(
      asOfDate: (json['asOfDate'] ?? '').toString(),
      tag2: tag2Raw is Map
          ? ShucaiReport.fromJson(Map<String, dynamic>.from(tag2Raw))
          : const ShucaiReport(columns: [], rows: []),
      tag3: tag3,
    );
  }
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
        }
      }
    }
    final rows = <Map<String, dynamic>>[];
    final rawRows = json['rows'];
    if (rawRows is List) {
      for (final item in rawRows) {
        if (item is Map) {
          rows.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return ShucaiReport(
      columns: cols,
      rows: rows,
      tab: (json['tab'] ?? '').toString(),
    );
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

String reconCardTitle(String cardType) {
  switch (cardType.toUpperCase()) {
    case 'TAG2':
      return '标签二 · 各省资金';
    case 'TAG3_ENERGY':
      return '标签三 · 能源';
    case 'TAG3_OPERATOR':
      return '标签三 · 运营商';
    default:
      return cardType;
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
      case 'TAG2_FINANCE':
        return '标签二财务';
      case 'TAG3_FINANCE':
        return '标签三财务';
      case 'ENERGY_L1':
        return '能源一层';
      case 'ENERGY_L2':
        return '能源二层';
      case 'OPERATOR_L1':
        return '运营商一层';
      case 'OPERATOR_L2':
        return '运营商二层';
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
  final bool canConfirm;
  final int expectedCount;
  final int confirmedCount;

  bool get confirmed => canConfirm && mine != null;
  bool get viewerOnly => !canConfirm;

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
    return ReconCardStatus(
      cardType: (json['cardType'] ?? '').toString(),
      asOfDate: (json['asOfDate'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      expected: parseList(json['expected']),
      acks: parseList(json['acks']),
      others: parseList(json['others']),
      mine: mine,
      myRole: (json['myRole'] ?? '').toString(),
      canConfirm: json.containsKey('canConfirm')
          ? json['canConfirm'] == true
          : (json['myRole'] ?? '').toString().toUpperCase() != 'FINAL',
      expectedCount: (json['expectedCount'] as num?)?.toInt() ?? 0,
      confirmedCount: (json['confirmedCount'] as num?)?.toInt() ?? 0,
    );
  }
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
    final key = cardType.toUpperCase();
    for (final item in cards) {
      if (item.cardType.toUpperCase() == key) return item;
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
