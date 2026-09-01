/// 进程被杀后残留的会议录音会话。
class AbandonedMeetingRecording {
  const AbandonedMeetingRecording({
    required this.title,
    required this.durationMs,
    required this.segmentCount,
  });

  final String title;
  final int durationMs;
  final int segmentCount;

  Duration get duration => Duration(milliseconds: durationMs.clamp(0, 24 * 60 * 60 * 1000));

  String get displayTitle {
    final t = title.trim();
    return t.isEmpty ? '未命名会议' : t;
  }
}

String formatAbandonedDuration(Duration duration) {
  final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
  if (total < 60) return '$total 秒';
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (minutes < 60) {
    return seconds == 0 ? '$minutes 分钟' : '$minutes 分 $seconds 秒';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '$hours 小时';
  return '$hours 小时 $rest 分钟';
}

String abandonedMeetingPrompt(AbandonedMeetingRecording rec) {
  return '「${rec.displayTitle}」约 ${formatAbandonedDuration(rec.duration)} 的录音'
      '因应用被清理而中断。已保存的部分可以恢复为草稿，避免纪要全部丢失。';
}
