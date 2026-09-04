String xflowBillFormatYmd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String xflowBillFormatYm(DateTime d) =>
    '${d.year} / ${d.month.toString().padLeft(2, '0')}';

({DateTime start, DateTime end}) xflowBillMonthBounds(DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 0);
  return (start: start, end: end);
}

({DateTime start, DateTime end})? xflowBillNormalizePeriod({
  DateTime? start,
  DateTime? end,
}) {
  if (start == null || end == null) return null;
  if (end.isBefore(start)) return (start: end, end: start);
  return (start: start, end: end);
}

DateTime? xflowBillParseInstant(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final cleaned = s.contains('.') && RegExp(r'\d{2}:\d{2}:\d{2}\.').hasMatch(s)
      ? s.split('.').first
      : s;
  for (final fmt in [
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-dd',
    'yyyy.MM.dd',
    'yyyy/MM/dd',
  ]) {
    try {
      return DateTime.parse(
        fmt == 'yyyy-MM-dd HH:mm:ss'
            ? cleaned.replaceFirst(' ', 'T')
            : fmt == 'yyyy.MM.dd'
            ? cleaned.replaceAll('.', '-')
            : fmt == 'yyyy/MM/dd'
            ? cleaned.replaceAll('/', '-')
            : cleaned,
      );
    } catch (_) {}
  }
  return DateTime.tryParse(cleaned);
}

String xflowBillCompactPeriod(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  const seps = [' 至 ', '至', ' 到 ', '到', ' ~ ', '~', ' — ', '—'];
  String? sep;
  for (final cand in seps) {
    if (s.contains(cand)) {
      sep = cand;
      break;
    }
  }
  if (sep == null) {
    if (s.contains(':')) {
      final t = xflowBillParseInstant(s);
      if (t != null) return xflowBillFormatYmd(t);
    }
    return s;
  }
  final parts = s.split(sep);
  if (parts.length < 2) return s;
  final start = xflowBillParseInstant(parts[0]);
  final end = xflowBillParseInstant(parts.sublist(1).join(sep));
  if (start == null || end == null) return s;
  var startD = DateTime(start.year, start.month, start.day);
  var endD = DateTime(end.year, end.month, end.day);
  if (endD.isBefore(startD)) {
    final tmp = startD;
    startD = endD;
    endD = tmp;
  }
  if (startD == endD) return xflowBillFormatYmd(startD);
  final last = DateTime(startD.year, startD.month + 1, 0);
  if (startD.day == 1 && endD == last) {
    return '${startD.year}.${startD.month.toString().padLeft(2, '0')}';
  }
  if (startD.year == endD.year) {
    String md(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${md(startD)}-${md(endD)}';
  }
  return '${xflowBillFormatYmd(startD)} 至 ${xflowBillFormatYmd(endD)}';
}

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

String xflowBillTypeNameOf(Map row) {
  final name = '${row['billTypeName'] ?? ''}'.trim();
  if (name.isNotEmpty) return name;
  return '${row['billTypeCode'] ?? ''}'.trim();
}

String xflowBillProjectNameOf(Map row) => '${row['projectName'] ?? ''}'.trim();

String xflowBillTypeProjectLine(Map row) {
  return [
    xflowBillTypeNameOf(row),
    xflowBillProjectNameOf(row),
  ].where((e) => e.isNotEmpty).join(' · ');
}

String xflowBillLabelOf(Map row) {
  final period = xflowBillCompactPeriod('${row['billPeriod'] ?? ''}');
  final composed = [
    '${row['ourEntityName'] ?? ''}'.trim(),
    '${row['counterpartyName'] ?? ''}'.trim(),
    period,
  ].where((e) => e.isNotEmpty).join(' - ');
  final label = '${row['label'] ?? ''}'.trim();
  if (label.isEmpty) return composed;
  if (RegExp(r'\d{2}:\d{2}:\d{2}').hasMatch(label)) return composed;
  return label;
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
    'billPeriod': xflowBillCompactPeriod('${src['billPeriod'] ?? ''}'.trim()),
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
