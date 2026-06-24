/// 与 WebView `msgTimeLabel` / `formatNovaHistoryTime` / `dayDividerLabel` 对齐（本地时区）。
DateTime? parseNovaDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
  }
  if (raw is num) {
    final n = raw.toInt();
    if (n > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal();
    }
    if (n > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
    }
  }
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

String novaMsgTimeLabel(DateTime? at) {
  final local = parseNovaDateTime(at);
  if (local == null) return '';
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _dayKey(DateTime d) {
  final local = d.toLocal();
  return '${local.year}-${local.month}-${local.day}';
}

String _cnWeekday(DateTime d) {
  const names = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return names[d.toLocal().weekday % 7];
}

String formatNovaHistoryTime(DateTime? at) {
  final local = parseNovaDateTime(at);
  if (local == null) return '';
  final now = DateTime.now();
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (_dayKey(local) == _dayKey(now)) return hm;
  final yesterday = now.subtract(const Duration(days: 1));
  if (_dayKey(local) == _dayKey(yesterday)) return '昨天 $hm';
  if (local.year == now.year) return '${local.month}/${local.day} $hm';
  return '${local.year}/${local.month}/${local.day}';
}

String? historyDayDividerLabel(DateTime? at, DateTime? prevAt) {
  final local = parseNovaDateTime(at);
  if (local == null) return null;
  final prev = parseNovaDateTime(prevAt);
  if (prev != null && _dayKey(local) == _dayKey(prev)) return null;
  final now = DateTime.now();
  final weekday = _cnWeekday(local);
  if (_dayKey(local) == _dayKey(now)) return '今天 · $weekday';
  final yesterday = now.subtract(const Duration(days: 1));
  if (_dayKey(local) == _dayKey(yesterday)) return '昨天 · $weekday';
  if (local.year == now.year) return '${local.month}月${local.day}日 · $weekday';
  return '${local.year}年${local.month}月${local.day}日 · $weekday';
}
