class NativeMeetingTime {
  static String formatDisplay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '未设置时间';
    final value = raw.trim();
    final extracted = _extractDateTime(value);
    if (extracted != null) return extracted;
    final epoch = int.tryParse(value);
    if (epoch != null && epoch > 0) {
      final ms = epoch >= 1000000000000 ? epoch : epoch * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      return _formatDateTime(dt);
    }
    final parsed = _parseToDateTime(value);
    if (parsed == null) {
      if (value.length >= 19 && value[10] == ' ') {
        return value.substring(0, 19);
      }
      return value;
    }
    return _formatDateTime(parsed.toLocal());
  }

  static String formatDisplayBest({
    String? createdAt,
    String? updatedAt,
    String? meetingDate,
  }) {
    final latest = _pickLatest(createdAt, updatedAt);
    if (latest != null) return _formatDateTime(latest.toLocal());
    final created = formatDisplay(createdAt);
    final updated = formatDisplay(updatedAt);
    if (_hasRealClock(updated)) return updated;
    if (_hasRealClock(created)) return created;
    if (updatedAt != null && updatedAt.trim().isNotEmpty) return updated;
    if (createdAt != null && createdAt.trim().isNotEmpty) return created;
    return formatDisplay(meetingDate);
  }

  static String _formatDateTime(DateTime local) {
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  static bool _hasRealClock(String text) {
    final m = RegExp(r' (\d{2}):(\d{2}):(\d{2})$').firstMatch(text);
    if (m == null) return false;
    return m.group(1) != '00' || m.group(2) != '00' || m.group(3) != '00';
  }

  static String? _extractDateTime(String value) {
    final m = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[T\s]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
    ).firstMatch(value);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    final d = int.tryParse(m.group(3) ?? '');
    if (y == null || mo == null || d == null) return null;
    final hh = int.tryParse(m.group(4) ?? '');
    final mm = int.tryParse(m.group(5) ?? '');
    final ss = int.tryParse(m.group(6) ?? '0') ?? 0;
    if (hh == null || mm == null) {
      // Keep date-only values readable, avoid fake 00:00:00.
      return '$y-${_two(mo)}-${_two(d)}';
    }
    return '$y-${_two(mo)}-${_two(d)} ${_two(hh)}:${_two(mm)}:${_two(ss)}';
  }

  static DateTime? _pickLatest(String? createdAt, String? updatedAt) {
    final created = _parseToDateTime(createdAt);
    final updated = _parseToDateTime(updatedAt);
    if (created == null) return updated;
    if (updated == null) return created;
    return updated.isAfter(created) ? updated : created;
  }

  static DateTime? _parseToDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final epoch = int.tryParse(value);
    if (epoch != null && epoch > 0) {
      final ms = epoch >= 1000000000000 ? epoch : epoch * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    var normalized =
        value.contains(' ') ? value.replaceFirst(' ', 'T') : value;
    // 后端 formatDateTime 在 UTC 容器里输出的是不带时区的 UTC 墙上时间，
    // 若字符串既有时间又没有时区标记，则按 UTC 解析，再由调用方 toLocal()
    // 转成设备本地时间（避免比北京时间少 8 小时）。
    final hasZone =
        RegExp(r'([Zz]|[+\-]\d{2}:?\d{2})$').hasMatch(normalized);
    if (!hasZone && normalized.contains('T')) {
      normalized = '${normalized}Z';
    }
    return DateTime.tryParse(normalized);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
