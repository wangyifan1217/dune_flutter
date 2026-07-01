class NativeMeetingTime {
  static String formatDisplay(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '未设置时间';
    final value = raw.trim();
    final epoch = int.tryParse(value);
    if (epoch != null && epoch > 0) {
      final ms = epoch >= 1000000000000 ? epoch : epoch * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      return _formatDateTime(dt);
    }
    if (value.length >= 19 && value[10] == ' ') {
      return value.substring(0, 19);
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return _formatDateTime(parsed.toLocal());
  }

  static String formatDisplayBest({
    String? createdAt,
    String? updatedAt,
    String? meetingDate,
  }) {
    final created = formatDisplay(createdAt);
    final updated = formatDisplay(updatedAt);
    if (_hasRealClock(created)) return created;
    if (_hasRealClock(updated)) return updated;
    if (createdAt != null && createdAt.trim().isNotEmpty) return created;
    if (updatedAt != null && updatedAt.trim().isNotEmpty) return updated;
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

  static String _two(int value) => value.toString().padLeft(2, '0');
}
