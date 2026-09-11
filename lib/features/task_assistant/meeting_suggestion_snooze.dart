/// 任务建议「稍后提醒」时间：几小时 / 几天，工作时间外顺延到 9:00。
DateTime meetingSuggestionRemindAt(
  String preset, {
  DateTime? now,
}) {
  final n = now?.toLocal() ?? DateTime.now();
  final at = switch (preset) {
    'tomorrow9' => DateTime(n.year, n.month, n.day + 1, 9),
    '3d9' => DateTime(n.year, n.month, n.day + 3, 9),
    _ => n.add(const Duration(hours: 2)),
  };
  return alignMeetingSnoozeToWorkHours(at);
}

DateTime alignMeetingSnoozeToWorkHours(DateTime at) {
  final local = at.toLocal();
  if (local.hour >= 8 && local.hour < 22) return local;
  if (local.hour >= 22) {
    return DateTime(local.year, local.month, local.day + 1, 9);
  }
  return DateTime(local.year, local.month, local.day, 9);
}

String meetingSnoozePresetLabel(String preset) {
  switch (preset) {
    case '2h':
      return '2 小时后';
    case 'tomorrow9':
      return '明天 9:00';
    case '3d9':
      return '3 天后 9:00';
    default:
      return '稍后';
  }
}

String formatMeetingSnoozeAt(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}
