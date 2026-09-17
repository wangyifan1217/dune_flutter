double tag3DailyNum(dynamic raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse('${raw ?? ''}') ?? 0;
}

String tag3DailyMoney(num value) => value.toStringAsFixed(2);

String tag3DailyPercent(num? rate) {
  if (rate == null) return '-';
  return '${(rate * 100).toStringAsFixed(2)}%';
}

int tag3DailyPeriodRank(String period) {
  switch (period.toUpperCase()) {
    case 'DAY':
      return 0;
    case 'PREV_MONTH':
      return 1;
    case 'MONTH':
      return 2;
    default:
      return 9;
  }
}

class Tag3DailyPerson {
  const Tag3DailyPerson({
    required this.userId,
    required this.name,
    required this.phone,
  });

  final String userId;
  final String name;
  final String phone;

  factory Tag3DailyPerson.fromJson(Map<String, dynamic> json) {
    return Tag3DailyPerson(
      userId: '${json['userId'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      phone: '${json['phone'] ?? ''}'.trim(),
    );
  }
}

class Tag3DailyAssignee {
  const Tag3DailyAssignee({
    required this.rowKey,
    required this.businessUsers,
    required this.operationUsers,
  });

  final String rowKey;
  final List<Tag3DailyPerson> businessUsers;
  final List<Tag3DailyPerson> operationUsers;

  factory Tag3DailyAssignee.fromJson(Map<String, dynamic> json) {
    List<Tag3DailyPerson> people(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw.whereType<Map>())
          Tag3DailyPerson.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    return Tag3DailyAssignee(
      rowKey: '${json['rowKey'] ?? ''}'.trim(),
      businessUsers: people(json['businessUsers']),
      operationUsers: people(json['operationUsers']),
    );
  }
}

String tag3DailyPersonNames(List<Tag3DailyPerson> people) {
  final names = [
    for (final person in people)
      if (person.name.trim().isNotEmpty) person.name.trim(),
  ];
  return names.isEmpty ? '未配置' : names.join('、');
}

class Tag3DailyAuditLane {
  const Tag3DailyAuditLane({
    required this.role,
    required this.names,
    required this.done,
  });

  final String role;
  final String names;
  final bool done;

  String get statusLabel => done ? '已确认' : '未确认';
}

bool tag3DailyRoleConfirmed({
  required String stage,
  required List<Tag3DailyPerson> people,
  required List<Tag3DailyComment> comments,
}) {
  final names = {
    for (final person in people)
      if (person.name.trim().isNotEmpty) person.name.trim(),
  };
  final want = stage.trim().toUpperCase();
  return comments.any((item) {
    if (!item.isConfirm) return false;
    if (item.stage.toUpperCase() == want) return true;
    return names.contains(item.userName.trim());
  });
}

List<Tag3DailyAuditLane> tag3DailyAuditLanes({
  Tag3DailyAssignee? assignee,
  List<Tag3DailyComment> comments = const [],
}) {
  return [
    Tag3DailyAuditLane(
      role: '业务',
      names: tag3DailyPersonNames(assignee?.businessUsers ?? const []),
      done: tag3DailyRoleConfirmed(
        stage: 'BUSINESS',
        people: assignee?.businessUsers ?? const [],
        comments: comments,
      ),
    ),
    Tag3DailyAuditLane(
      role: '运营',
      names: tag3DailyPersonNames(assignee?.operationUsers ?? const []),
      done: tag3DailyRoleConfirmed(
        stage: 'OPERATION',
        people: assignee?.operationUsers ?? const [],
        comments: comments,
      ),
    ),
  ];
}

String tag3DailyConfirmButtonLabel(String? stage) {
  return '确认';
}

String tag3DailyStatDateDay(String raw) {
  final value = raw.trim();
  if (value.length >= 10) return value.substring(0, 10);
  return value;
}

String tag3DailyCommentTime(String raw) {
  final dt = DateTime.tryParse(raw.trim());
  if (dt == null) return raw.trim();
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class Tag3DailyComment {
  const Tag3DailyComment({
    required this.id,
    required this.rowKey,
    required this.period,
    required this.statDate,
    required this.periodLabel,
    required this.projectName,
    required this.userId,
    required this.userName,
    required this.kind,
    this.stage = '',
    required this.body,
    required this.createdAt,
  });

  final int id;
  final String rowKey;
  final String period;
  final String statDate;
  final String periodLabel;
  final String projectName;
  final int userId;
  final String userName;
  final String kind;
  final String stage;
  final String body;
  final String createdAt;

  bool get isConfirm => kind.toUpperCase() == 'CONFIRM';

  String get kindLabel => isConfirm ? '确认' : '意见';

  String get displayBody {
    final text = body.trim();
    if (text.isNotEmpty) return text;
    return isConfirm ? '已确认，未填写意见' : '';
  }

  bool matchesRow(Tag3DailyRow row) {
    return rowKey == row.rowKey &&
        period.toUpperCase() == row.period &&
        tag3DailyStatDateDay(statDate) == row.statDateDay;
  }

  factory Tag3DailyComment.fromJson(Map<String, dynamic> json) {
    return Tag3DailyComment(
      id: tag3DailyNum(json['id']).round(),
      rowKey: '${json['rowKey'] ?? ''}'.trim(),
      period: '${json['period'] ?? ''}'.trim().toUpperCase(),
      statDate: tag3DailyStatDateDay('${json['statDate'] ?? ''}'),
      periodLabel: '${json['periodLabel'] ?? ''}'.trim(),
      projectName: '${json['projectName'] ?? ''}'.trim(),
      userId: tag3DailyNum(json['userId']).round(),
      userName: '${json['userName'] ?? ''}'.trim(),
      kind: '${json['kind'] ?? ''}'.trim().toUpperCase(),
      stage: '${json['stage'] ?? ''}'.trim().toUpperCase(),
      body: '${json['body'] ?? ''}'.trim(),
      createdAt: '${json['createdAt'] ?? ''}'.trim(),
    );
  }
}

class Tag3DailyRow {
  const Tag3DailyRow({
    required this.rowKey,
    required this.channelCategoryL1Name,
    required this.projectName,
    required this.period,
    required this.periodLabel,
    required this.statDate,
    required this.paymentTerm,
    required this.salesAmount,
    required this.writeOffAmount,
    required this.profitAmount,
    required this.cashFlowAmount,
    required this.cashReceivableAmount,
    required this.cashPaidAmount,
    required this.cashReceivableDiff,
    required this.subsidyReceivableAmount,
    required this.confirmationStatus,
    required this.confirmationStatusLabel,
    required this.canConfirm,
    this.canComment = false,
    this.canConfirmStage,
    this.sourceTab = '',
  });

  final String rowKey;
  final String channelCategoryL1Name;
  final String projectName;
  final String period;
  final String periodLabel;
  final String statDate;
  final String paymentTerm;
  final double salesAmount;
  final double writeOffAmount;
  final double profitAmount;
  final double cashFlowAmount;
  final double cashReceivableAmount;
  final double cashPaidAmount;
  final double cashReceivableDiff;
  final double subsidyReceivableAmount;
  final String confirmationStatus;
  final String confirmationStatusLabel;
  final bool canConfirm;
  final bool canComment;
  final String? canConfirmStage;
  final String sourceTab;

  String get statDateDay => tag3DailyStatDateDay(statDate);

  bool get isMonthCumulative => period == 'MONTH';

  bool get showCommentAction => canComment && !isMonthCumulative;

  bool get showConfirmAction =>
      canConfirm && (canConfirmStage ?? '').isNotEmpty && !isMonthCumulative;

  String get actionId => '$rowKey|$period|$statDateDay|$periodLabel';

  factory Tag3DailyRow.fromJson(Map<String, dynamic> json) {
    final stage = '${json['canConfirmStage'] ?? ''}'.trim();
    final period = '${json['period'] ?? ''}'.trim().toUpperCase();
    final canCommentRaw = json['canComment'];
    return Tag3DailyRow(
      rowKey: '${json['rowKey'] ?? ''}'.trim(),
      channelCategoryL1Name: '${json['channelCategoryL1Name'] ?? ''}'.trim(),
      projectName: '${json['projectName'] ?? ''}'.trim(),
      period: period,
      periodLabel: '${json['periodLabel'] ?? ''}'.trim(),
      statDate: '${json['statDate'] ?? ''}'.trim(),
      paymentTerm: '${json['paymentTerm'] ?? ''}'.trim(),
      salesAmount: tag3DailyNum(json['salesAmount']),
      writeOffAmount: tag3DailyNum(json['writeOffAmount']),
      profitAmount: tag3DailyNum(json['profitAmount']),
      cashFlowAmount: tag3DailyNum(json['cashFlowAmount']),
      cashReceivableAmount: tag3DailyNum(json['cashReceivableAmount']),
      cashPaidAmount: tag3DailyNum(json['cashPaidAmount']),
      cashReceivableDiff: tag3DailyNum(json['cashReceivableDiff']),
      subsidyReceivableAmount: tag3DailyNum(json['subsidyReceivableAmount']),
      confirmationStatus: '${json['confirmationStatus'] ?? ''}'.trim().toUpperCase(),
      confirmationStatusLabel: '${json['confirmationStatusLabel'] ?? ''}'.trim(),
      canConfirm: json['canConfirm'] == true && period != 'MONTH',
      canComment: period != 'MONTH' && canCommentRaw != false,
      canConfirmStage: stage.isEmpty || period == 'MONTH' ? null : stage.toUpperCase(),
      sourceTab: '${json['sourceTab'] ?? ''}'.trim(),
    );
  }
}

class Tag3DailySnapshot {
  const Tag3DailySnapshot({
    required this.asOfDate,
    required this.rows,
    required this.assignees,
    this.comments = const [],
  });

  final String asOfDate;
  final List<Tag3DailyRow> rows;
  final List<Tag3DailyAssignee> assignees;
  final List<Tag3DailyComment> comments;

  factory Tag3DailySnapshot.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rawAssignees = json['assignees'];
    final rawComments = json['comments'];
    return Tag3DailySnapshot(
      asOfDate: '${json['asOfDate'] ?? ''}'.trim(),
      rows: rawRows is List
          ? [
              for (final item in rawRows.whereType<Map>())
                Tag3DailyRow.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      assignees: rawAssignees is List
          ? [
              for (final item in rawAssignees.whereType<Map>())
                Tag3DailyAssignee.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      comments: rawComments is List
          ? [
              for (final item in rawComments.whereType<Map>())
                Tag3DailyComment.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }

  List<Tag3DailyComment> commentsFor(Tag3DailyRow row) {
    return [for (final item in comments) if (item.matchesRow(row)) item];
  }

  Tag3DailyAssignee? assigneeFor(String rowKey) {
    final key = rowKey.trim();
    for (final item in assignees) {
      if (item.rowKey == key) return item;
    }
    return null;
  }

  List<Tag3DailyRow> get confirmableRows {
    return [
      for (final row in sortTag3DailyRows(rows))
        if (row.showConfirmAction) row,
    ];
  }
}

class Tag3DailyDrilldownItem {
  const Tag3DailyDrilldownItem({
    required this.provinceName,
    required this.periodLabel,
    required this.statDate,
    required this.productName,
    required this.salesAmount,
    required this.writeOffAmount,
    required this.profitAmount,
    required this.profitRate,
    required this.cashReceivableAmount,
    required this.receivableAmount,
  });

  final String provinceName;
  final String periodLabel;
  final String statDate;
  final String productName;
  final double salesAmount;
  final double writeOffAmount;
  final double profitAmount;
  final double? profitRate;
  final double cashReceivableAmount;
  final double receivableAmount;

  factory Tag3DailyDrilldownItem.fromJson(Map<String, dynamic> json) {
    final rateRaw = json['profitRate'];
    return Tag3DailyDrilldownItem(
      provinceName: '${json['provinceName'] ?? ''}'.trim(),
      periodLabel: '${json['periodLabel'] ?? ''}'.trim(),
      statDate: '${json['statDate'] ?? ''}'.trim(),
      productName: '${json['productName'] ?? ''}'.trim(),
      salesAmount: tag3DailyNum(json['salesAmount']),
      writeOffAmount: tag3DailyNum(json['writeOffAmount']),
      profitAmount: tag3DailyNum(json['profitAmount']),
      profitRate: rateRaw == null ? null : tag3DailyNum(rateRaw),
      cashReceivableAmount: tag3DailyNum(json['cashReceivableAmount']),
      receivableAmount: tag3DailyNum(json['receivableAmount']),
    );
  }
}

class Tag3DailyDrilldown {
  const Tag3DailyDrilldown({
    required this.metricKey,
    required this.items,
    required this.totalSales,
    required this.totalWriteOff,
    required this.totalProfit,
  });

  final String metricKey;
  final List<Tag3DailyDrilldownItem> items;
  final double totalSales;
  final double totalWriteOff;
  final double totalProfit;

  factory Tag3DailyDrilldown.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return Tag3DailyDrilldown(
      metricKey: '${json['metricKey'] ?? ''}'.trim(),
      items: raw is List
          ? [
              for (final item in raw.whereType<Map>())
                Tag3DailyDrilldownItem.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      totalSales: tag3DailyNum(json['totalSales']),
      totalWriteOff: tag3DailyNum(json['totalWriteOff']),
      totalProfit: tag3DailyNum(json['totalProfit']),
    );
  }
}

bool isTag3DailyCard(String cardType) =>
    cardType.trim().toUpperCase() == 'TAG3_DAILY';

List<Tag3DailyRow> sortTag3DailyRows(List<Tag3DailyRow> rows) {
  final out = [...rows];
  out.sort((a, b) {
    final c = a.channelCategoryL1Name.compareTo(b.channelCategoryL1Name);
    if (c != 0) return c;
    final p = a.projectName.compareTo(b.projectName);
    if (p != 0) return p;
    final pr = tag3DailyPeriodRank(a.period).compareTo(tag3DailyPeriodRank(b.period));
    if (pr != 0) return pr;
    return a.statDateDay.compareTo(b.statDateDay);
  });
  return out;
}
