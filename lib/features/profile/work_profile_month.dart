bool isSameWorkProfileMonth(DateTime? value, DateTime month) {
  return value != null &&
      value.year == month.year &&
      value.month == month.month;
}

double clampWorkProfileRadarValue(num value, {required num cap}) {
  if (cap <= 0) return 0;
  final ratio = value / cap;
  if (ratio <= 0) return 0;
  if (ratio >= 1) return 1;
  return ratio.toDouble();
}
