import 'native_meeting_models.dart';

enum MeetingExportFormat {
  markdown('md'),
  plainText('txt');

  const MeetingExportFormat(this.extension);
  final String extension;

  String get label => switch (this) {
        MeetingExportFormat.markdown => 'Markdown',
        MeetingExportFormat.plainText => '文本',
      };
}

class MeetingMinutesExport {
  MeetingMinutesExport._();

  static bool canExport(NativeMeetingDetail detail) {
    final status = detail.status.toUpperCase();
    if (status == 'DRAFT' ||
        status == 'TRANSCRIBING' ||
        status == 'GENERATING') {
      return false;
    }
    return detail.summary.trim().isNotEmpty ||
        detail.actionItems.isNotEmpty ||
        detail.transcriptSegments.isNotEmpty;
  }

  static String fileName(NativeMeetingDetail detail, MeetingExportFormat format) {
    final title = detail.title.trim();
    final base = title.isNotEmpty
        ? title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'meeting-${detail.meetingId}';
    return '$base.${format.extension}';
  }

  static String buildMarkdown(NativeMeetingDetail detail) {
    final buf = StringBuffer();
    final title = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : '未命名会议';

    buf.writeln('# $title');
    buf.writeln();
    if (detail.meetingDate.trim().isNotEmpty) {
      buf.writeln('- **会议日期**：${detail.meetingDate.trim()}');
    }
    buf.writeln('- **记录时间**：${detail.displayTime}');
    buf.writeln();

    final summary = detail.summary.trim();
    buf.writeln('## 会议摘要');
    buf.writeln();
    buf.writeln(summary.isNotEmpty ? summary : '（暂无摘要）');
    buf.writeln();

    if (detail.actionItems.isNotEmpty) {
      buf.writeln('## 待办事项');
      buf.writeln();
      for (final item in detail.actionItems) {
        final text = item.trim();
        if (text.isNotEmpty) buf.writeln('- $text');
      }
      buf.writeln();
    }

    if (detail.transcriptSegments.isNotEmpty) {
      buf.writeln('## 原始逐句转写');
      buf.writeln();
      for (final seg in detail.transcriptSegments) {
        final speaker = seg.speaker.trim().isNotEmpty ? seg.speaker.trim() : '发言人';
        buf.writeln('### $speaker · ${_formatMs(seg.startMs)}');
        buf.writeln();
        buf.writeln(seg.text.trim());
        buf.writeln();
      }
    }

    return buf.toString().trimRight();
  }

  static String buildPlainText(NativeMeetingDetail detail) {
    final buf = StringBuffer();
    final title = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : '未命名会议';

    buf.writeln(title);
    buf.writeln('=' * title.length.clamp(4, 40));
    if (detail.meetingDate.trim().isNotEmpty) {
      buf.writeln('会议日期：${detail.meetingDate.trim()}');
    }
    buf.writeln('记录时间：${detail.displayTime}');
    buf.writeln();

    final summary = detail.summary.trim();
    buf.writeln('【会议摘要】');
    buf.writeln(summary.isNotEmpty ? summary : '（暂无摘要）');
    buf.writeln();

    if (detail.actionItems.isNotEmpty) {
      buf.writeln('【待办事项】');
      for (var i = 0; i < detail.actionItems.length; i++) {
        final text = detail.actionItems[i].trim();
        if (text.isNotEmpty) buf.writeln('${i + 1}. $text');
      }
      buf.writeln();
    }

    if (detail.transcriptSegments.isNotEmpty) {
      buf.writeln('【原始逐句转写】');
      for (final seg in detail.transcriptSegments) {
        final speaker = seg.speaker.trim().isNotEmpty ? seg.speaker.trim() : '发言人';
        buf.writeln('');
        buf.writeln('[$speaker ${_formatMs(seg.startMs)}]');
        buf.writeln(seg.text.trim());
      }
    }

    return buf.toString().trimRight();
  }

  static String _formatMs(int ms) {
    final d = Duration(milliseconds: ms.clamp(0, 24 * 60 * 60 * 1000));
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
