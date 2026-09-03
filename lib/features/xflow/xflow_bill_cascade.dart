num? xflowBillNum(dynamic raw) {
  if (raw is num) return raw;
  if (raw == null) return null;
  return num.tryParse(raw.toString().trim());
}

int? xflowBillId(dynamic raw) {
  if (raw is Map) {
    return xflowBillId(raw['billId'] ?? raw['id']);
  }
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse('${raw ?? ''}'.trim());
}

bool xflowBillHasId(Map row, int id) => xflowBillId(row) == id;

double xflowBillPrimaryRemaining(Map row, String remainingKind) {
  if (remainingKind.trim() == 'invoice') {
    return (xflowBillNum(row['remainingInvoiceable']) ??
            xflowBillNum(row['remainingInvoiceAmount']) ??
            0)
        .toDouble();
  }
  return (xflowBillNum(row['remainingPayable']) ??
          ((xflowBillNum(row['billAmount']) ?? 0) -
              (xflowBillNum(row['paidAmount']) ?? 0)))
      .toDouble()
      .clamp(0, double.infinity)
      .toDouble();
}

List<String> xflowBillAmountLabels(
  String remainingKind, {
  String billDirection = '',
}) {
  if (remainingKind.trim() == 'invoice') {
    return const ['默认金额', '已开票', '剩余可开'];
  }
  if (billDirection.toUpperCase() == 'AR') {
    return const ['默认金额', '已还', '剩余应还'];
  }
  return const ['默认金额', '已付', '剩余应付'];
}

String xflowBillLabelOf(Map row) {
  final label = '${row['label'] ?? ''}'.trim();
  if (label.isNotEmpty) return label;
  final parts = <String>[
    '${row['ourEntityName'] ?? ''}'.trim(),
    '${row['counterpartyName'] ?? ''}'.trim(),
    '${row['billPeriod'] ?? ''}'.trim(),
  ].where((e) => e.isNotEmpty).toList();
  return parts.join(' - ');
}

String xflowBillMoney(dynamic raw) {
  final n = xflowBillNum(raw);
  if (n == null) return '—';
  return '${n.toStringAsFixed(2)} 元';
}

List<String> xflowBillAmountValues(Map row, String remainingKind) {
  final mid = remainingKind.trim() == 'invoice'
      ? xflowBillMoney(row['invoiceAmount'])
      : xflowBillMoney(row['paidAmount']);
  return [
    xflowBillMoney(row['billAmount']),
    mid,
    xflowBillMoney(xflowBillPrimaryRemaining(row, remainingKind)),
  ];
}

String xflowBillAmountLine(
  Map row,
  String remainingKind, {
  String billDirection = '',
}) {
  final labels = xflowBillAmountLabels(
    remainingKind,
    billDirection: billDirection,
  );
  final values = xflowBillAmountValues(row, remainingKind);
  return '${labels[0]} ${values[0]}  ·  ${labels[1]} ${values[1]}  ·  ${labels[2]} ${values[2]}';
}

double xflowBillSelectedRemainingSum(
  List<Map<String, dynamic>> rows,
  String remainingKind,
) {
  var sum = 0.0;
  for (final row in rows) {
    sum += xflowBillPrimaryRemaining(row, remainingKind);
  }
  return sum;
}

String xflowBillRemainingSummaryLabel(
  String remainingKind, {
  String billDirection = '',
}) {
  return '${xflowBillAmountLabels(remainingKind, billDirection: billDirection)[2]}合计';
}

String xflowBillPreviewLine(
  Map row,
  String remainingKind, {
  String billDirection = '',
}) {
  final label = xflowBillLabelOf(row);
  final kind = xflowBillAmountLabels(
    remainingKind,
    billDirection: billDirection,
  )[2];
  final left = xflowBillMoney(xflowBillPrimaryRemaining(row, remainingKind));
  if (label.isEmpty) return '$kind $left';
  return '$label（$kind $left）';
}

Map<String, dynamic> xflowBillSnapshot(
  Map row, {
  required String remainingKind,
  String billDirection = '',
}) {
  final src = Map<String, dynamic>.from(row);
  final id = xflowBillId(src);
  final payable =
      (xflowBillNum(src['remainingPayable']) ??
              xflowBillPrimaryRemaining(src, 'payable'))
          .toDouble();
  final invoiceable =
      (xflowBillNum(src['remainingInvoiceable']) ??
              xflowBillPrimaryRemaining(src, 'invoice'))
          .toDouble();
  final dir = '${src['billDirection'] ?? ''}'.trim();
  return {
    'billId': id,
    'billNo': '${src['billNo'] ?? ''}'.trim(),
    'billDirection': dir.isNotEmpty ? dir : billDirection.trim(),
    'ourEntityName': '${src['ourEntityName'] ?? ''}'.trim(),
    'counterpartyName': '${src['counterpartyName'] ?? ''}'.trim(),
    'billPeriod': '${src['billPeriod'] ?? ''}'.trim(),
    'billStartDate': '${src['billStartDate'] ?? ''}'.trim(),
    'billEndDate': '${src['billEndDate'] ?? ''}'.trim(),
    'projectName': '${src['projectName'] ?? ''}'.trim(),
    'billTypeCode': '${src['billTypeCode'] ?? ''}'.trim(),
    'billTypeName': '${src['billTypeName'] ?? ''}'.trim(),
    'billAmount': xflowBillNum(src['billAmount']) ?? 0,
    'paidAmount': xflowBillNum(src['paidAmount']) ?? 0,
    'invoiceAmount': xflowBillNum(src['invoiceAmount']) ?? 0,
    'remainingPayable': payable,
    'remainingInvoiceable': invoiceable,
    'remainingAmount': remainingKind.trim() == 'invoice'
        ? invoiceable
        : payable,
    'label': xflowBillLabelOf(src),
  };
}

List<Map<String, dynamic>> xflowBillSelectedList(dynamic raw) {
  if (raw is List) {
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
  if (raw is Map) return [Map<String, dynamic>.from(raw)];
  return const [];
}

class XflowBillCascadeConfig {
  const XflowBillCascadeConfig({
    required this.billDirection,
    this.remainingKind = 'payable',
  });

  final String billDirection;
  final String remainingKind;

  factory XflowBillCascadeConfig.fromField(Map<String, dynamic> raw) {
    final dir = '${raw['billDirection'] ?? ''}'.trim().toUpperCase();
    final kind = '${raw['remainingKind'] ?? ''}'.trim().toLowerCase();
    return XflowBillCascadeConfig(
      billDirection: dir == 'AR' || dir == 'AP' ? dir : 'AR',
      remainingKind: kind == 'invoice' ? 'invoice' : 'payable',
    );
  }
}
