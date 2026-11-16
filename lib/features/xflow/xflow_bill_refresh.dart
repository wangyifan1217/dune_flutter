import 'dart:async';
import 'xflow_bill_cascade.dart';
import 'xflow_models.dart';

typedef XflowBillPageFetcher =
    Future<List<Map<String, dynamic>>> Function({
      required String billDirection,
      required String billTypeCode,
      required String dateStart,
      required String dateEnd,
      required int pageNum,
    });

class XflowBillRefreshResult {
  const XflowBillRefreshResult({
    required this.form,
    required this.total,
    required this.updated,
  });
  final Map<String, dynamic> form;
  final int total, updated;
  int get failed => total - updated;
}

({String start, String end})? xflowBillLookupDates(Map row) {
  DateTime? parse(dynamic value) => xflowBillParseInstant('${value ?? ''}');
  var start = parse(row['lookupDateStart']);
  var end = parse(row['lookupDateEnd']);
  if (start != null && end != null && !end.isBefore(start))
    return (start: xflowBillFormatYmd(start), end: xflowBillFormatYmd(end));
  start = parse(row['billStartDate']);
  end = parse(row['billEndDate']);
  if (start != null || end != null) {
    start ??= end;
    end ??= start;
    final bounds = xflowBillNormalizePeriod(start: start, end: end)!;
    final first = xflowBillMonthBounds(bounds.start).start;
    final last = xflowBillMonthBounds(bounds.end).end;
    return (start: xflowBillFormatYmd(first), end: xflowBillFormatYmd(last));
  }
  final period = '${row['billPeriod'] ?? ''}'.trim();
  final monthly = RegExp(r'^(\d{4})[./-](\d{1,2})$').firstMatch(period);
  if (monthly != null) {
    final month = int.parse(monthly.group(2)!);
    if (month < 1 || month > 12) return null;
    final bounds = xflowBillMonthBounds(
      DateTime(int.parse(monthly.group(1)!), month),
    );
    return (
      start: xflowBillFormatYmd(bounds.start),
      end: xflowBillFormatYmd(bounds.end),
    );
  }
  final range = period.split(RegExp(r'\s*(?:至|到|~|—)\s*'));
  if (range.length == 2) {
    final from = parse(range[0]), to = parse(range[1]);
    if (from != null && to != null) {
      final bounds = xflowBillNormalizePeriod(start: from, end: to)!;
      return (
        start: xflowBillFormatYmd(xflowBillMonthBounds(bounds.start).start),
        end: xflowBillFormatYmd(xflowBillMonthBounds(bounds.end).end),
      );
    }
  }
  final day = parse(period);
  if (day == null || !RegExp(r'^\d{4}[-./]').hasMatch(period)) return null;
  final bounds = xflowBillMonthBounds(day);
  return (
    start: xflowBillFormatYmd(bounds.start),
    end: xflowBillFormatYmd(bounds.end),
  );
}

List<({String start, String end})> xflowBillLookupCandidates(
  Map row,
  DateTime? createdAt,
) {
  final explicit = xflowBillLookupDates(row);
  if (explicit != null) return [explicit];
  if (createdAt == null) return [];
  // Older snapshots abbreviated same-year periods as MM.dd-MM.dd. Search a
  // bounded set of years, but accept results only when the stable bill ID matches.
  final period = '${row['billPeriod'] ?? ''}'.trim();
  final match = RegExp(
    r'^(\d{1,2})\.(\d{1,2})-(\d{1,2})\.(\d{1,2})$',
  ).firstMatch(period);
  if (match == null) return [];
  final startMonth = int.parse(match.group(1)!);
  final startDay = int.parse(match.group(2)!);
  final endMonth = int.parse(match.group(3)!);
  final endDay = int.parse(match.group(4)!);
  if (startMonth < 1 ||
      startMonth > 12 ||
      endMonth < 1 ||
      endMonth > 12 ||
      startDay < 1 ||
      startDay > 31 ||
      endDay < 1 ||
      endDay > 31)
    return [];
  return [
    for (var offset = 0; offset < 4; offset++)
      (
        start: xflowBillFormatYmd(
          DateTime(createdAt.year - offset, startMonth, 1),
        ),
        end: xflowBillFormatYmd(
          DateTime(
            createdAt.year - offset + (endMonth < startMonth ? 1 : 0),
            endMonth + 1,
            0,
          ),
        ),
      ),
  ];
}

/// Refresh only display copies. Never writes to the submitted approval snapshot.
Future<XflowBillRefreshResult> refreshXflowApprovalBills({
  required Map<String, dynamic> form,
  required List<XflowField> fields,
  required XflowBillPageFetcher fetch,
  DateTime? createdAt,
}) async {
  final next = Map<String, dynamic>.from(form);
  final groups =
      <
        String,
        List<
          ({
            String fieldKey,
            int index,
            int id,
            String direction,
            String type,
            String start,
            String end,
            String kind,
          })
        >
      >{};
  var total = 0;
  var updated = 0;
  for (final field in fields.where((f) => f.type == 'billCascade')) {
    final cfg = XflowBillCascadeConfig.fromField(field.raw);
    final rows = xflowBillSelectedList(form[field.key]);
    if (rows.isEmpty) continue;
    next[field.key] = rows;
    for (var i = 0; i < rows.length; i++) {
      total++;
      final row = rows[i];
      row['_billRefreshState'] = 'unavailable';
      final id = xflowBillId(row);
      final direction = '${row['billDirection'] ?? cfg.billDirection}'
          .trim()
          .toUpperCase();
      final type = '${row['billTypeCode'] ?? ''}'.trim();
      final candidates = xflowBillLookupCandidates(row, createdAt);
      if (id == null ||
          id <= 0 ||
          (direction != 'AP' && direction != 'AR') ||
          type.isEmpty)
        continue;
      for (final dates in candidates) {
        final groupKey =
            '$direction\u0000$type\u0000${dates.start}\u0000${dates.end}';
        groups.putIfAbsent(groupKey, () => []).add((
          fieldKey: field.key,
          index: i,
          id: id,
          direction: direction,
          type: type,
          start: dates.start,
          end: dates.end,
          kind: cfg.remainingKind,
        ));
      }
    }
  }
  final elapsed = Stopwatch()..start();
  for (final targets in groups.values) {
    final first = targets.first;
    final pending = targets
        .where(
          (t) =>
              (next[t.fieldKey] as List<Map<String, dynamic>>)[t
                  .index]['_billRefreshState'] !=
              'updated',
        )
        .map((t) => t.id)
        .toSet();
    try {
      for (var page = 1; page <= 100 && pending.isNotEmpty; page++) {
        if (elapsed.elapsed >= const Duration(seconds: 20)) break;
        final rows = await fetch(
          billDirection: first.direction,
          billTypeCode: first.type,
          dateStart: first.start,
          dateEnd: first.end,
          pageNum: page,
        ).timeout(const Duration(seconds: 8));
        for (final live in rows) {
          final id = xflowBillId(live);
          if (id == null || !pending.contains(id)) continue;
          for (final target in targets.where((t) => t.id == id)) {
            final required = target.kind == 'invoice'
                ? 'invoiceAmount'
                : 'paidAmount';
            if (xflowBillNum(live['billAmount']) == null ||
                xflowBillNum(live[required]) == null)
              continue;
            final list = next[target.fieldKey] as List<Map<String, dynamic>>;
            final original = list[target.index];
            if (original['_billRefreshState'] == 'updated') continue;
            final merged = <String, dynamic>{...original};
            for (final key in [
              'billNo',
              'ourEntityName',
              'counterpartyName',
              'billPeriod',
              'billStartDate',
              'billEndDate',
              'projectName',
              'provinceName',
              'billTypeCode',
              'billTypeName',
              'label',
              'billAmount',
              'paidAmount',
              'invoiceAmount',
              'remainingPayable',
              'remainingInvoiceable',
              'reconcileAmount',
              'pnlAmount',
              'reconcileRemark',
              'reconcileStatus',
              'reconcileStatusLabel',
            ]) {
              if (live.containsKey(key)) merged[key] = live[key];
            }
            if (live.keys.any(
              (key) => key.toLowerCase().contains('province'),
            )) {
              merged['provinceName'] = xflowBillProvinceOf(live);
            }
            final amountKey = target.kind == 'invoice'
                ? 'remainingInvoiceable'
                : 'remainingPayable';
            if (live[amountKey] != null)
              merged['remainingAmount'] = live[amountKey];
            merged['_billRefreshState'] = 'updated';
            list[target.index] = merged;
            updated++;
          }
          pending.remove(id);
        }
        if (rows.length < 200) break;
      }
    } catch (_) {
      // Keep each unmatched original and mark it unavailable.
    }
  }
  return XflowBillRefreshResult(form: next, total: total, updated: updated);
}
