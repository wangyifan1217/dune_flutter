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

  /// 上传到知识库时的文件名与展示标题：`会议纪要-{用户填写标题}.md`
  static String kbUploadFileName(NativeMeetingDetail detail) {
    return '${kbUploadBaseName(detail)}.md';
  }

  static String kbUploadTitle(NativeMeetingDetail detail) {
    return kbUploadBaseName(detail);
  }

  static String kbUploadBaseName(NativeMeetingDetail detail) {
    return _kbUploadBaseName(
      title: detail.title,
      meetingId: detail.meetingId,
    );
  }

  static String kbUploadFileNameFromSummary(NativeMeetingSummary summary) {
    return '${kbUploadTitleFromSummary(summary)}.md';
  }

  static String kbUploadTitleFromSummary(NativeMeetingSummary summary) {
    return _kbUploadBaseName(
      title: summary.title,
      meetingId: summary.meetingId,
    );
  }

  static String _kbUploadBaseName({
    required String title,
    required int meetingId,
  }) {
    final trimmed = title.trim();
    final base = trimmed.isNotEmpty
        ? trimmed.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_')
        : (meetingId > 0 ? '会议$meetingId' : '未命名会议');
    return '会议纪要-$base';
  }

  /// PRD 附件文件名：`PRD-{用户标题}.md`
  static String prdFileName(NativeMeetingDetail detail) {
    final title = detail.title.trim();
    final base = title.isNotEmpty
        ? title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_')
        : (detail.meetingId > 0 ? '会议${detail.meetingId}' : '未命名会议');
    return 'PRD-$base.md';
  }

  static bool isListItemLikelyExportable(NativeMeetingSummary summary) {
    final status = summary.status.toUpperCase();
    if (status == 'DRAFT' ||
        status == 'TRANSCRIBING' ||
        status == 'GENERATING') {
      return false;
    }
    return (summary.summary?.trim().isNotEmpty ?? false);
  }

  @Deprecated('Use kbUploadFileName(NativeMeetingDetail) instead')
  static String kbUploadFileNameLegacy(int meetingId) {
    if (meetingId <= 0) return 'meeting-minutes.md';
    return 'meeting-minutes-$meetingId.md';
  }

  static String buildMarkdown(NativeMeetingDetail detail) =>
      _buildMarkdownBody(detail, includeTranscript: true);

  /// 上传到知识库：仅摘要与待办，不含原始逐句转写。
  static String buildKbUploadMarkdown(NativeMeetingDetail detail) =>
      _buildMarkdownBody(detail, includeTranscript: false);

  /// 发给 NOVA 的会议纪要附件：不含逐句转写，避免请求体过大导致 chat/completions 失败。
  static String buildAttachmentMarkdown(NativeMeetingDetail detail) =>
      buildKbUploadMarkdown(detail);

  /// 仅含会议摘要的 Markdown（本地生成附件，再发给 NOVA 生成 PRD）。
  static String buildSummaryMarkdown(NativeMeetingDetail detail) {
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
    buf.writeln('## 会议摘要');
    buf.writeln();
    final summary = detail.summary.trim();
    buf.writeln(summary.isNotEmpty ? summary : '（暂无摘要）');
    return buf.toString().trimRight();
  }

  /// 摘要 MD 附件文件名。
  static String summaryMarkdownFileName(NativeMeetingDetail detail) {
    return '${kbUploadBaseName(detail)}-摘要.md';
  }

  static String _buildMarkdownBody(
    NativeMeetingDetail detail, {
    required bool includeTranscript,
  }) {
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

    if (includeTranscript && detail.transcriptSegments.isNotEmpty) {
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
