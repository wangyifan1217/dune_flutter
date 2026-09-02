class FundSecondmentRow {
  const FundSecondmentRow({
    required this.id,
    required this.loanDocId,
    required this.code,
    required this.borrowSubject,
    required this.paySubject,
    required this.borrowAmountWan,
    this.estimatedRepaymentDate = '',
    this.approvedAt = '',
    this.borrowReason = '',
    this.settled = false,
    this.repaidTotalWan = 0,
    this.remainingWan = 0,
  });

  final int id;
  final int loanDocId;
  final String code;
  final String borrowSubject;
  final String paySubject;
  final double borrowAmountWan;
  final String estimatedRepaymentDate;
  final String approvedAt;
  final String borrowReason;
  final bool settled;
  final double repaidTotalWan;
  final double remainingWan;

  bool get isCleared => settled || remainingWan <= 0;

  String get statusLabel {
    if (isCleared) return '已还清';
    if (repaidTotalWan > 0) return '部分还款';
    return '未还款';
  }

  factory FundSecondmentRow.fromJson(Map<String, dynamic> json) {
    return FundSecondmentRow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      loanDocId: (json['loanDocId'] as num?)?.toInt() ?? 0,
      code: '${json['code'] ?? ''}'.trim(),
      borrowSubject: '${json['borrowSubject'] ?? ''}'.trim(),
      paySubject: '${json['paySubject'] ?? ''}'.trim(),
      borrowAmountWan: (json['borrowAmountWan'] as num?)?.toDouble() ?? 0,
      estimatedRepaymentDate: '${json['estimatedRepaymentDate'] ?? ''}'.trim(),
      approvedAt: fundSecondmentDateOnly('${json['approvedAt'] ?? ''}'),
      borrowReason: '${json['borrowReason'] ?? ''}'.trim(),
      settled: json['settled'] == true,
      repaidTotalWan: (json['repaidTotalWan'] as num?)?.toDouble() ?? 0,
      remainingWan: (json['remainingWan'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FundSecondmentSubjectBucket {
  const FundSecondmentSubjectBucket({
    required this.subject,
    this.count = 0,
    this.remainingWan = 0,
  });

  final String subject;
  final int count;
  final double remainingWan;

  factory FundSecondmentSubjectBucket.fromJson(Map<String, dynamic> json) {
    return FundSecondmentSubjectBucket(
      subject: '${json['subject'] ?? ''}'.trim(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      remainingWan: (json['remainingWan'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FundSecondmentRouteBucket {
  const FundSecondmentRouteBucket({
    required this.borrowSubject,
    required this.paySubject,
    this.count = 0,
    this.remainingWan = 0,
  });

  final String borrowSubject;
  final String paySubject;
  final int count;
  final double remainingWan;

  factory FundSecondmentRouteBucket.fromJson(Map<String, dynamic> json) {
    return FundSecondmentRouteBucket(
      borrowSubject: '${json['borrowSubject'] ?? ''}'.trim(),
      paySubject: '${json['paySubject'] ?? ''}'.trim(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      remainingWan: (json['remainingWan'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FundSecondmentSummary {
  const FundSecondmentSummary({
    this.count = 0,
    this.settledCount = 0,
    this.unsettledCount = 0,
    this.borrowTotalWan = 0,
    this.repaidTotalWan = 0,
    this.remainingTotalWan = 0,
    this.overdueCount = 0,
    this.overdueRemainingWan = 0,
    this.dueSoonCount = 0,
    this.dueSoonRemainingWan = 0,
    this.borrowers = const [],
    this.lenders = const [],
    this.routes = const [],
  });

  final int count;
  final int settledCount;
  final int unsettledCount;
  final double borrowTotalWan;
  final double repaidTotalWan;
  final double remainingTotalWan;
  final int overdueCount;
  final double overdueRemainingWan;
  final int dueSoonCount;
  final double dueSoonRemainingWan;
  final List<FundSecondmentSubjectBucket> borrowers;
  final List<FundSecondmentSubjectBucket> lenders;
  final List<FundSecondmentRouteBucket> routes;

  double get repaidRatio {
    if (borrowTotalWan <= 0) return remainingTotalWan > 0 ? 0 : 1;
    final ratio = repaidTotalWan / borrowTotalWan;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  factory FundSecondmentSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FundSecondmentSummary();
    final count = (json['count'] as num?)?.toInt() ?? 0;
    final settled = (json['settledCount'] as num?)?.toInt() ?? 0;
    var unsettled = (json['unsettledCount'] as num?)?.toInt();
    unsettled ??= count - settled;
    if (unsettled < 0) unsettled = 0;
    return FundSecondmentSummary(
      count: count,
      settledCount: settled,
      unsettledCount: unsettled,
      borrowTotalWan: (json['borrowTotalWan'] as num?)?.toDouble() ?? 0,
      repaidTotalWan: (json['repaidTotalWan'] as num?)?.toDouble() ?? 0,
      remainingTotalWan: (json['remainingTotalWan'] as num?)?.toDouble() ?? 0,
      overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
      overdueRemainingWan: (json['overdueRemainingWan'] as num?)?.toDouble() ?? 0,
      dueSoonCount: (json['dueSoonCount'] as num?)?.toInt() ?? 0,
      dueSoonRemainingWan: (json['dueSoonRemainingWan'] as num?)?.toDouble() ?? 0,
      borrowers: _parseSubjectBuckets(json['borrowers']),
      lenders: _parseSubjectBuckets(json['lenders']),
      routes: _parseRouteBuckets(json['routes']),
    );
  }
}

List<FundSecondmentSubjectBucket> _parseSubjectBuckets(dynamic raw) {
  return (raw as List? ?? const [])
      .whereType<Map>()
      .map((e) => FundSecondmentSubjectBucket.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.subject.isNotEmpty)
      .toList(growable: false);
}

List<FundSecondmentRouteBucket> _parseRouteBuckets(dynamic raw) {
  return (raw as List? ?? const [])
      .whereType<Map>()
      .map((e) => FundSecondmentRouteBucket.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

String formatFundSecondmentWan(double v) {
  if (v == v.roundToDouble()) return '${v.toInt()}万';
  return '${v.toStringAsFixed(2)}万';
}

class FundSecondmentListPageResult {
  const FundSecondmentListPageResult({
    required this.items,
    required this.totalCount,
    this.summary = const FundSecondmentSummary(),
  });

  final List<FundSecondmentRow> items;
  final int totalCount;
  final FundSecondmentSummary summary;
}

class FundSecondmentRepayment {
  const FundSecondmentRepayment({
    required this.id,
    required this.date,
    required this.amountWan,
  });

  final int id;
  final String date;
  final double amountWan;

  factory FundSecondmentRepayment.fromJson(Map<String, dynamic> json) {
    return FundSecondmentRepayment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      date: '${json['date'] ?? ''}'.trim(),
      amountWan: (json['amountWan'] as num?)?.toDouble() ?? 0,
    );
  }
}

class FundSecondmentDetail {
  const FundSecondmentDetail({
    required this.row,
    required this.repayments,
  });

  final FundSecondmentRow row;
  final List<FundSecondmentRepayment> repayments;

  factory FundSecondmentDetail.fromJson(Map<String, dynamic> json) {
    final repayments = (json['repayments'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => FundSecondmentRepayment.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return FundSecondmentDetail(
      row: FundSecondmentRow.fromJson(json),
      repayments: repayments,
    );
  }
}

/// 审批通过时间只展示年月日。
String fundSecondmentDateOnly(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == 'null') return '';
  final parsed = DateTime.tryParse(text);
  if (parsed != null) {
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  final m = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(text);
  if (m == null) return '';
  return '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}';
}
