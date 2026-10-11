import 'tag2_entity_models.dart';
import 'tag3_daily_models.dart';

/// One scope for list progress and detail summaries: visible detail rows only.
class ReconReportProgress {
  const ReconReportProgress({
    required this.total,
    required this.businessConfirmed,
    required this.operationConfirmed,
    required this.opinions,
    required this.mine,
    required this.completed,
  });

  final int total, businessConfirmed, operationConfirmed, opinions, completed;
  final bool mine;

  String get line => total == 0
      ? '暂无需确认的明细'
      : '业务已确认 $businessConfirmed/$total 条 · 运营已确认 $operationConfirmed/$total 条 · 意见 $opinions 条';

  String get pill => total > 0 && completed == total
      ? '全部完成'
      : mine
      ? '你已有确认'
      : businessConfirmed > 0 || operationConfirmed > 0
      ? '确认中'
      : '待确认';
}

List<Tag3DailyAuditLane> tag2EntityAuditLanes(
  Tag2EntityRow row,
  List<Tag3DailyComment> history,
) => [
  Tag3DailyAuditLane(
    role: '业务',
    names: row.businessBy.isEmpty && row.confirmationStatus == 'WAIT_BUSINESS'
        ? row.currentHandlers
        : row.businessBy,
    done: row.confirmationStatus.isNotEmpty
        ? row.confirmationStatus == 'WAIT_OPERATION' ||
              row.confirmationStatus == 'ALL_CONFIRMED'
        : history.any((c) => c.isConfirm && c.stage == 'BUSINESS'),
  ),
  Tag3DailyAuditLane(
    role: '运营',
    names: row.operationBy.isEmpty && row.confirmationStatus == 'WAIT_OPERATION'
        ? row.currentHandlers
        : row.operationBy,
    done: row.confirmationStatus.isNotEmpty
        ? row.confirmationStatus == 'ALL_CONFIRMED'
        : history.any((c) => c.isConfirm && c.stage == 'OPERATION'),
  ),
];

ReconReportProgress tag3ReportProgress(Tag3DailySnapshot snapshot, int userId) {
  var business = 0, operation = 0, completed = 0;
  var mine = false;
  final rows = <String, Tag3DailyRow>{
    for (final row in snapshot.rows)
      if (!row.isMonthCumulative) row.actionId: row,
  }.values;
  final opinions = <int>{};
  for (final row in rows) {
    final history = snapshot.commentsFor(row);
    final lanes = tag3DailyAuditLanes(
      assignee: snapshot.assigneeFor(row.rowKey),
      comments: history,
      row: row,
    );
    if (lanes[0].done) business++;
    if (lanes[1].done) operation++;
    if (lanes.every((lane) => lane.done)) completed++;
    mine =
        mine ||
        history.any((c) => c.isConfirm && c.userId == userId && userId > 0);
    opinions.addAll(
      history.where((c) => c.isOpinion || c.isReject).map((c) => c.id),
    );
  }
  return ReconReportProgress(
    total: rows.length,
    businessConfirmed: business,
    operationConfirmed: operation,
    opinions: opinions.length,
    mine: mine,
    completed: completed,
  );
}

ReconReportProgress tag2ReportProgress(
  Tag2EntitySnapshot snapshot,
  int userId,
) {
  var business = 0, operation = 0, completed = 0;
  var mine = false;
  final rows = <String, Tag2EntityRow>{
    for (final row in snapshot.rows)
      if (!row.isTotal) row.rowKey: row,
  }.values;
  final opinions = <int>{};
  for (final row in rows) {
    final history = snapshot.commentsFor(row.rowKey);
    final lanes = tag2EntityAuditLanes(row, history);
    if (lanes[0].done) business++;
    if (lanes[1].done) operation++;
    if (lanes.every((lane) => lane.done)) completed++;
    mine =
        mine ||
        history.any((c) => c.isConfirm && c.userId == userId && userId > 0);
    opinions.addAll(
      history.where((c) => c.isOpinion || c.isReject).map((c) => c.id),
    );
  }
  return ReconReportProgress(
    total: rows.length,
    businessConfirmed: business,
    operationConfirmed: operation,
    opinions: opinions.length,
    mine: mine,
    completed: completed,
  );
}

/// Blank, non-numeric and percentage cells must not silently become money.
double? reconSummaryAmount(String display) {
  final value = display.trim().replaceAll(',', '').replaceAll('，', '');
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite ? parsed : null;
}

String reconSummaryMoney(num amount) {
  if (!amount.isFinite) return '—';
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  if (parts.length != 2) return fixed;
  final integer = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$integer.${parts[1]}';
}
