/// 月结看板静态样例。口径对齐沙丘文档：两表 UNION、渠道/供给看 SUPPLIER|、
/// 未对账对账金额当 0、清 0 差异当 0。接真库后只换数据源。
class MonthlyBillRow {
  const MonthlyBillRow({
    required this.id,
    required this.billNo,
    required this.side,
    required this.kind,
    required this.period,
    required this.typeName,
    required this.amountYuan,
    required this.reconcileYuan,
    required this.counterparty,
    required this.ourEntity,
    required this.projectName,
    required this.province,
    required this.termDays,
    required this.overdueDays,
    required this.paidYuan,
    required this.payDiffYuan,
  });

  /// `receivable` / `payable`
  final String side;

  /// `channel` / `supply`
  final String kind;
  final String id;
  final String billNo;
  final String period;
  final String typeName;
  final double amountYuan;
  final double reconcileYuan;
  final String counterparty;
  final String ourEntity;
  final String projectName;
  final String province;
  final int termDays;
  final int overdueDays;
  final double paidYuan;
  final double payDiffYuan;

  bool get isOverdue => overdueDays > 0;
  double get unpaidYuan => (amountYuan - paidYuan).clamp(0, double.infinity);

  factory MonthlyBillRow.fromJson(Map<String, dynamic> json) {
    return MonthlyBillRow(
      id: '${json['id'] ?? ''}',
      billNo: '${json['billNo'] ?? ''}',
      side: '${json['side'] ?? ''}',
      kind: '${json['kind'] ?? ''}',
      period: '${json['period'] ?? ''}',
      typeName: '${json['typeName'] ?? ''}',
      amountYuan: _asDouble(json['amountYuan']),
      reconcileYuan: _asDouble(json['reconcileYuan']),
      counterparty: '${json['counterparty'] ?? ''}',
      ourEntity: '${json['ourEntity'] ?? ''}',
      projectName: '${json['projectName'] ?? ''}',
      province: '${json['province'] ?? ''}',
      termDays: _asInt(json['termDays']),
      overdueDays: _asInt(json['overdueDays']),
      paidYuan: _asDouble(json['paidYuan']),
      payDiffYuan: _asDouble(json['payDiffYuan']),
    );
  }
}

class MonthlyBillKpi {
  const MonthlyBillKpi({
    required this.count,
    required this.amountYuan,
    required this.reconcileYuan,
    required this.paidYuan,
    required this.unpaidYuan,
    required this.payDiffYuan,
    required this.overdueCount,
    required this.overdueAmountYuan,
    required this.channelYuan,
    required this.supplyYuan,
  });

  final int count;
  final double amountYuan;
  final double reconcileYuan;
  final double paidYuan;
  final double unpaidYuan;
  final double payDiffYuan;
  final int overdueCount;
  final double overdueAmountYuan;
  final double channelYuan;
  final double supplyYuan;

  factory MonthlyBillKpi.fromJson(Map<String, dynamic> json) {
    return MonthlyBillKpi(
      count: _asInt(json['count']),
      amountYuan: _asDouble(json['amountYuan']),
      reconcileYuan: _asDouble(json['reconcileYuan']),
      paidYuan: _asDouble(json['paidYuan']),
      unpaidYuan: _asDouble(json['unpaidYuan']),
      payDiffYuan: _asDouble(json['payDiffYuan']),
      overdueCount: _asInt(json['overdueCount']),
      overdueAmountYuan: _asDouble(json['overdueAmountYuan']),
      channelYuan: _asDouble(json['channelYuan']),
      supplyYuan: _asDouble(json['supplyYuan']),
    );
  }
}

const MonthlyBillKpi monthlyBillKpiEmpty = MonthlyBillKpi(
  count: 0,
  amountYuan: 0,
  reconcileYuan: 0,
  paidYuan: 0,
  unpaidYuan: 0,
  payDiffYuan: 0,
  overdueCount: 0,
  overdueAmountYuan: 0,
  channelYuan: 0,
  supplyYuan: 0,
);

class MonthlyBillBoard {
  const MonthlyBillBoard({
    required this.month,
    required this.from,
    required this.to,
    required this.receivable,
    required this.payable,
    this.rows = const [],
  });

  final String month;
  final String from;
  final String to;
  final MonthlyBillKpi receivable;
  final MonthlyBillKpi payable;
  final List<MonthlyBillRow> rows;

  factory MonthlyBillBoard.fromJson(Map<String, dynamic> json) {
    List<MonthlyBillRow> rows = const [];
    final raw = json['rows'];
    if (raw is List) {
      rows = raw
          .whereType<Map>()
          .map((e) => MonthlyBillRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
    return MonthlyBillBoard(
      month: '${json['month'] ?? ''}',
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      receivable: json['receivable'] is Map
          ? MonthlyBillKpi.fromJson(Map<String, dynamic>.from(json['receivable'] as Map))
          : monthlyBillKpiEmpty,
      payable: json['payable'] is Map
          ? MonthlyBillKpi.fromJson(Map<String, dynamic>.from(json['payable'] as Map))
          : monthlyBillKpiEmpty,
      rows: rows,
    );
  }
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

List<String> monthlyBillMonthOptions({DateTime? now}) {
  final n = now ?? DateTime.now();
  final out = <String>[];
  var y = n.year;
  var m = n.month;
  for (var i = 0; i < 12; i++) {
    out.add(
      '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}',
    );
    m -= 1;
    if (m == 0) {
      m = 12;
      y -= 1;
    }
  }
  return out.reversed.toList(growable: false);
}

String monthlyBillDefaultMonth({DateTime? now}) {
  final n = now ?? DateTime.now();
  final prev = DateTime(n.year, n.month - 1, 1);
  return '${prev.year.toString().padLeft(4, '0')}-${prev.month.toString().padLeft(2, '0')}';
}

MonthlyBillKpi monthlyBillKpiOf(Iterable<MonthlyBillRow> rows) {
  var count = 0;
  var amount = 0.0;
  var reconcile = 0.0;
  var paid = 0.0;
  var unpaid = 0.0;
  var diff = 0.0;
  var overdueCount = 0;
  var overdueAmount = 0.0;
  var channel = 0.0;
  var supply = 0.0;
  for (final r in rows) {
    count += 1;
    amount += r.amountYuan;
    reconcile += r.reconcileYuan;
    paid += r.paidYuan;
    unpaid += r.unpaidYuan;
    diff += r.payDiffYuan;
    if (r.kind == 'supply') {
      supply += r.amountYuan;
    } else {
      channel += r.amountYuan;
    }
    if (r.isOverdue) {
      overdueCount += 1;
      overdueAmount += r.unpaidYuan;
    }
  }
  return MonthlyBillKpi(
    count: count,
    amountYuan: amount,
    reconcileYuan: reconcile,
    paidYuan: paid,
    unpaidYuan: unpaid,
    payDiffYuan: diff,
    overdueCount: overdueCount,
    overdueAmountYuan: overdueAmount,
    channelYuan: channel,
    supplyYuan: supply,
  );
}

String monthlyBillKindLabel(String kind, {required bool payable}) {
  if (kind == 'supply') return payable ? '供应商' : '供给';
  return '渠道';
}

String monthlyBillSideLabel(String side) => side == 'payable' ? '应付' : '应收';

String monthlyBillFmtYuan(double yuan) {
  final wan = yuan / 10000;
  if (wan.abs() >= 10000) {
    return '${(wan / 10000).toStringAsFixed(2)} 亿';
  }
  if (wan.abs() >= 100) {
    return '${wan.toStringAsFixed(0)} 万';
  }
  if (wan.abs() >= 1) {
    return '${wan.toStringAsFixed(1)} 万';
  }
  return '${yuan.toStringAsFixed(0)} 元';
}

MonthlyBillBoard monthlyBillDemoBoard(String month) {
  final rows = month == '2026-07' ? _julyRows : _augustRows;
  final from = month == '2026-07' ? '2026-07-01' : '2026-08-01';
  final to = month == '2026-07' ? '2026-07-31' : '2026-08-31';
  return MonthlyBillBoard(
    month: month,
    from: from,
    to: to,
    receivable: monthlyBillKpiOf(rows.where((r) => r.side == 'receivable')),
    payable: monthlyBillKpiOf(rows.where((r) => r.side == 'payable')),
    rows: rows,
  );
}

const _our = '上海卓悦优泰新能源科技有限公司';

const _augustRows = <MonthlyBillRow>[
  MonthlyBillRow(
    id: 'ar-1',
    billNo: 'AR-20260815-513',
    side: 'receivable',
    kind: 'channel',
    period: '2026-08-01 至 2026-08-31',
    typeName: '电子券销售款',
    amountYuan: 28640000,
    reconcileYuan: 28640000,
    counterparty: '中国平安财产保险股份有限公司',
    ourEntity: _our,
    projectName: '平安(共享平台)',
    province: '',
    termDays: 30,
    overdueDays: 12,
    paidYuan: 12000000,
    payDiffYuan: 16640000,
  ),
  MonthlyBillRow(
    id: 'ar-2',
    billNo: 'AR-20260820-088',
    side: 'receivable',
    kind: 'channel',
    period: '2026-08-01 至 2026-08-31',
    typeName: '平台服务费',
    amountYuan: 4120000,
    reconcileYuan: 0,
    counterparty: '支付宝（中国）网络技术有限公司',
    ourEntity: _our,
    projectName: '支付宝多渠道',
    province: '',
    termDays: 15,
    overdueDays: 0,
    paidYuan: 0,
    payDiffYuan: 4120000,
  ),
  MonthlyBillRow(
    id: 'ar-3',
    billNo: 'AR-20260811-204',
    side: 'receivable',
    kind: 'supply',
    period: '2026-07-01 至 2026-08-31',
    typeName: '应收返利',
    amountYuan: 9380000,
    reconcileYuan: 9380000,
    counterparty: '中国石油天然气股份有限公司广东销售分公司',
    ourEntity: _our,
    projectName: '',
    province: '广东省',
    termDays: 45,
    overdueDays: 6,
    paidYuan: 5000000,
    payDiffYuan: 4380000,
  ),
  MonthlyBillRow(
    id: 'ar-4',
    billNo: 'AR-20260828-331',
    side: 'receivable',
    kind: 'supply',
    period: '2026-08-01 至 2026-08-31',
    typeName: '应收返利',
    amountYuan: 2150000,
    reconcileYuan: 2150000,
    counterparty: '中国石油天然气股份有限公司内蒙古销售分公司',
    ourEntity: _our,
    projectName: '',
    province: '内蒙古自治区',
    termDays: 45,
    overdueDays: 0,
    paidYuan: 2150000,
    payDiffYuan: 0,
  ),
  MonthlyBillRow(
    id: 'ap-1',
    billNo: 'AP-20260816-077',
    side: 'payable',
    kind: 'supply',
    period: '2026-08-01 至 2026-08-31',
    typeName: '电子券采购款',
    amountYuan: 24180000,
    reconcileYuan: 24180000,
    counterparty: '中国石油天然气股份有限公司广东销售分公司',
    ourEntity: _our,
    projectName: '',
    province: '',
    termDays: 7,
    overdueDays: 3,
    paidYuan: 18000000,
    payDiffYuan: 6180000,
  ),
  MonthlyBillRow(
    id: 'ap-2',
    billNo: 'AP-20260822-119',
    side: 'payable',
    kind: 'channel',
    period: '2026-08-01 至 2026-08-31',
    typeName: '渠道服务费分润',
    amountYuan: 1860000,
    reconcileYuan: 1860000,
    counterparty: '上海安壹通电子商务有限公司',
    ourEntity: _our,
    projectName: '平安(共享平台)',
    province: '',
    termDays: 30,
    overdueDays: 0,
    paidYuan: 1860000,
    payDiffYuan: 0,
  ),
  MonthlyBillRow(
    id: 'ap-3',
    billNo: 'AP-20260809-044',
    side: 'payable',
    kind: 'supply',
    period: '2026-08-01 至 2026-08-31',
    typeName: '电子券采购款',
    amountYuan: 6720000,
    reconcileYuan: 0,
    counterparty: '中国石化销售股份有限公司浙江石油分公司',
    ourEntity: _our,
    projectName: '',
    province: '',
    termDays: 7,
    overdueDays: 18,
    paidYuan: 0,
    payDiffYuan: 6720000,
  ),
];

const _julyRows = <MonthlyBillRow>[
  MonthlyBillRow(
    id: 'ar-j1',
    billNo: 'AR-20260718-201',
    side: 'receivable',
    kind: 'channel',
    period: '2026-07-01 至 2026-07-31',
    typeName: '电子券销售款',
    amountYuan: 25120000,
    reconcileYuan: 25120000,
    counterparty: '中国平安财产保险股份有限公司',
    ourEntity: _our,
    projectName: '平安(共享平台)',
    province: '',
    termDays: 30,
    overdueDays: 0,
    paidYuan: 25120000,
    payDiffYuan: 0,
  ),
  MonthlyBillRow(
    id: 'ar-j2',
    billNo: 'AR-20260725-066',
    side: 'receivable',
    kind: 'supply',
    period: '2026-06-01 至 2026-07-31',
    typeName: '应收返利',
    amountYuan: 7400000,
    reconcileYuan: 7400000,
    counterparty: '中国石油天然气股份有限公司广东销售分公司',
    ourEntity: _our,
    projectName: '',
    province: '广东省',
    termDays: 45,
    overdueDays: 2,
    paidYuan: 4000000,
    payDiffYuan: 3400000,
  ),
  MonthlyBillRow(
    id: 'ap-j1',
    billNo: 'AP-20260712-033',
    side: 'payable',
    kind: 'supply',
    period: '2026-07-01 至 2026-07-31',
    typeName: '电子券采购款',
    amountYuan: 19850000,
    reconcileYuan: 19850000,
    counterparty: '中国石油天然气股份有限公司广东销售分公司',
    ourEntity: _our,
    projectName: '',
    province: '',
    termDays: 7,
    overdueDays: 0,
    paidYuan: 19850000,
    payDiffYuan: 0,
  ),
  MonthlyBillRow(
    id: 'ap-j2',
    billNo: 'AP-20260729-091',
    side: 'payable',
    kind: 'channel',
    period: '2026-07-01 至 2026-07-31',
    typeName: '支付手续费',
    amountYuan: 940000,
    reconcileYuan: 940000,
    counterparty: '上海安壹通电子商务有限公司',
    ourEntity: _our,
    projectName: '平安(共享平台)',
    province: '',
    termDays: 30,
    overdueDays: 9,
    paidYuan: 200000,
    payDiffYuan: 740000,
  ),
];
