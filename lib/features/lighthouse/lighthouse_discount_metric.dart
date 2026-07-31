String lighthouseDiscountRateLabel(double? decimalRate) {
  if (decimalRate == null) return '—';
  final fixed = (decimalRate * 100).toStringAsFixed(2);
  final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return '$trimmed%';
}

String? lighthouseDiscountDateRange(String? startRaw, String? endRaw) {
  if (startRaw == null || endRaw == null) return null;
  final start = DateTime.tryParse(
    startRaw.length >= 10 ? startRaw.substring(0, 10) : startRaw,
  );
  final end = DateTime.tryParse(
    endRaw.length >= 10 ? endRaw.substring(0, 10) : endRaw,
  );
  if (start == null || end == null) return null;
  String md(DateTime date) =>
      '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  return '${md(start)}–${md(end)}';
}

/// 折扣区直接消费 /discounts 返回的 map，不依赖当期供给行是否挂载成功。
List<Map<String, dynamic>> lighthouseDiscountRowsFromMap(
  Map<String, dynamic> discounts,
) {
  final out = <Map<String, dynamic>>[];
  discounts.forEach((name, raw) {
    if (raw is! Map) return;
    final row = Map<String, dynamic>.from(raw);
    row.putIfAbsent('province', () => name);
    final cur =
        (row['currentCumSales'] as num?)?.toDouble() ??
        (row['cur'] as num?)?.toDouble() ??
        0;
    if (cur <= 0) return;
    out.add(row);
  });
  return out;
}
