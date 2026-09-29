import 'tag3_daily_models.dart';

bool isTag2EntityCard(String cardType) =>
    cardType.trim().toUpperCase() == 'TAG2_ENTITY';

class Tag2EntityAmount {
  const Tag2EntityAmount({
    required this.key,
    required this.label,
    required this.display,
    required this.drill,
  });

  final String key;
  final String label;
  final String display;
  final bool drill;

  factory Tag2EntityAmount.fromJson(Map<String, dynamic> json) {
    return Tag2EntityAmount(
      key: '${json['key'] ?? ''}'.trim(),
      label: '${json['label'] ?? ''}'.trim(),
      display: '${json['display'] ?? ''}'.trim(),
      drill: json['drill'] == true,
    );
  }
}

class Tag2EntityRow {
  const Tag2EntityRow({
    required this.rowKey,
    required this.rowType,
    required this.provinceName,
    required this.supplierName,
    required this.counterpartyName,
    required this.ourEntityName,
    required this.confirmationStatus,
    required this.confirmationStatusLabel,
    required this.canConfirmStage,
    required this.currentHandlers,
    required this.businessBy,
    required this.operationBy,
    required this.amounts,
  });

  final String rowKey;
  final String rowType;
  final String provinceName;
  final String supplierName;
  final String counterpartyName;
  final String ourEntityName;
  final String confirmationStatus;
  final String confirmationStatusLabel;
  final String canConfirmStage;
  final String currentHandlers;
  final String businessBy;
  final String operationBy;
  final List<Tag2EntityAmount> amounts;

  bool get isTotal => rowType.toUpperCase() == 'TOTAL';

  bool get showConfirm =>
      !isTotal &&
      (canConfirmStage == 'BUSINESS' || canConfirmStage == 'OPERATION');

  bool get showComment => !isTotal;

  String get title {
    final bits = [
      provinceName,
      counterpartyName,
      ourEntityName,
    ].where((item) => item.trim().isNotEmpty).toList();
    if (bits.isNotEmpty) return bits.join(' · ');
    if (isTotal) return '合计';
    return rowKey;
  }

  String get statusLabel {
    final label = confirmationStatusLabel.trim();
    if (label.isNotEmpty) return label;
    switch (confirmationStatus) {
      case 'WAIT_BUSINESS':
        return '待业务确认';
      case 'WAIT_OPERATION':
        return '待运营确认';
      case 'ALL_CONFIRMED':
        return '已全部确认';
      default:
        return isTotal ? '合计' : '';
    }
  }

  factory Tag2EntityRow.fromJson(Map<String, dynamic> json) {
    final raw = json['amounts'];
    return Tag2EntityRow(
      rowKey: '${json['rowKey'] ?? ''}'.trim(),
      rowType: '${json['rowType'] ?? ''}'.trim().toUpperCase(),
      provinceName: '${json['provinceName'] ?? ''}'.trim(),
      supplierName: '${json['supplierName'] ?? ''}'.trim(),
      counterpartyName: '${json['counterpartyName'] ?? ''}'.trim(),
      ourEntityName: '${json['ourEntityName'] ?? ''}'.trim(),
      confirmationStatus: '${json['confirmationStatus'] ?? ''}'
          .trim()
          .toUpperCase(),
      confirmationStatusLabel: '${json['confirmationStatusLabel'] ?? ''}'.trim(),
      canConfirmStage: '${json['canConfirmStage'] ?? ''}'.trim().toUpperCase(),
      currentHandlers: '${json['currentHandlers'] ?? ''}'.trim(),
      businessBy: '${json['businessBy'] ?? ''}'.trim(),
      operationBy: '${json['operationBy'] ?? ''}'.trim(),
      amounts: raw is List
          ? [
              for (final item in raw)
                if (item is Map)
                  Tag2EntityAmount.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }
}

class Tag2EntitySnapshot {
  const Tag2EntitySnapshot({
    required this.asOfDate,
    required this.rows,
    required this.comments,
    this.snapshotHint = '',
  });

  final String asOfDate;
  final List<Tag2EntityRow> rows;
  final List<Tag3DailyComment> comments;
  final String snapshotHint;

  List<Tag3DailyComment> commentsFor(String rowKey) {
    return [
      for (final item in comments)
        if (item.rowKey == rowKey) item,
    ];
  }

  factory Tag2EntitySnapshot.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rawComments = json['comments'];
    return Tag2EntitySnapshot(
      asOfDate: '${json['asOfDate'] ?? ''}'.trim(),
      snapshotHint: '${json['snapshotHint'] ?? ''}'.trim(),
      rows: rawRows is List
          ? [
              for (final item in rawRows)
                if (item is Map)
                  Tag2EntityRow.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      comments: rawComments is List
          ? [
              for (final item in rawComments)
                if (item is Map)
                  Tag3DailyComment.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }
}

class Tag2EntityDrilldown {
  const Tag2EntityDrilldown({required this.kind, required this.rows});

  final String kind;
  final List<Map<String, dynamic>> rows;

  factory Tag2EntityDrilldown.fromJson(Map<String, dynamic> json) {
    final raw = json['rows'];
    return Tag2EntityDrilldown(
      kind: '${json['kind'] ?? ''}'.trim(),
      rows: raw is List
          ? [
              for (final item in raw)
                if (item is Map) Map<String, dynamic>.from(item),
            ]
          : const [],
    );
  }
}

const tag2EntityDrillLabels = <String, String>{
  'billNo': '账单编号',
  'billTypeName': '账单类型',
  'ourEntityName': '我方主体',
  'counterpartyName': '对方主体',
  'projectName': '项目',
  'billStartDate': '账期开始',
  'billEndDate': '账期结束',
  'billAmount': '账单金额',
  'paidAmount': '已回款',
  'payDiff': '回款差异',
  'supplierName': '供应商',
  'mappingPeriodStart': '拆分账期开始',
  'mappingPeriodEnd': '拆分账期结束',
  'fullPeriodStart': '完整账期开始',
  'fullPeriodEnd': '完整账期结束',
  'paymentAmount': '付款金额',
  'settlementAmount': '结算金额',
  'beginningBalance': '期初余额',
  'prepaymentBalance': '预付款余额',
};
