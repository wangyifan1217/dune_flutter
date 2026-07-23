import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import 'robot_models.dart';

MarkdownStyleSheet? _cachedStyle;
MarkdownStyleSheet? _cachedCompactStyle;

MarkdownStyleSheet _robotMdStyle({required bool compact}) {
  final cached = compact ? _cachedCompactStyle : _cachedStyle;
  if (cached != null) return cached;

  final baseSize = compact ? 12.0 : 13.0;
  final tableSize = compact ? 11.0 : 12.0;
  final sheet = MarkdownStyleSheet(
    p: TextStyle(
      fontSize: baseSize,
      height: 1.55,
      color: RobotTheme.text2,
    ),
    h1: TextStyle(
      fontSize: compact ? 15 : 17,
      fontWeight: FontWeight.w700,
      color: RobotTheme.text,
      height: 1.35,
    ),
    h2: TextStyle(
      fontSize: compact ? 14 : 15,
      fontWeight: FontWeight.w700,
      color: RobotTheme.text,
      height: 1.35,
    ),
    h3: TextStyle(
      fontSize: compact ? 13 : 14,
      fontWeight: FontWeight.w700,
      color: RobotTheme.text,
      height: 1.35,
    ),
    strong: const TextStyle(
      fontWeight: FontWeight.w700,
      color: RobotTheme.text,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    code: TextStyle(
      fontSize: baseSize - 1,
      color: RobotTheme.text,
      backgroundColor: const Color(0xFFF0F1F4),
    ),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xFFF0F1F4),
      borderRadius: BorderRadius.circular(8),
    ),
    listBullet: TextStyle(
      fontSize: baseSize,
      color: RobotTheme.text3,
      height: 1.55,
    ),
    blockquote: TextStyle(
      fontSize: baseSize,
      color: RobotTheme.text3,
      height: 1.5,
    ),
    blockquoteDecoration: const BoxDecoration(
      border: Border(
        left: BorderSide(color: RobotTheme.purple, width: 3),
      ),
    ),
    a: const TextStyle(
      color: RobotTheme.purpleDeep,
      decoration: TextDecoration.underline,
    ),
    // Intrinsic + 包内横向滚动：宽表不再被气泡压扁。
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableHead: TextStyle(
      fontSize: tableSize,
      fontWeight: FontWeight.w700,
      color: RobotTheme.text,
      height: 1.35,
    ),
    tableBody: TextStyle(
      fontSize: tableSize,
      color: RobotTheme.text2,
      height: 1.35,
    ),
    tableBorder: TableBorder.all(color: const Color(0xFFE6E6EA), width: 0.5),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    tableHeadAlign: TextAlign.center,
  );
  if (compact) {
    _cachedCompactStyle = sheet;
  } else {
    _cachedStyle = sheet;
  }
  return sheet;
}

/// 灯塔机器人回复 Markdown 渲染（结论 / 节点 reply）。
class RobotMarkdown extends StatelessWidget {
  const RobotMarkdown({
    super.key,
    required this.markdown,
    this.compact = false,
    /// 会话流里关闭可选中，显著降低重排/手势开销。
    this.selectable = true,
  });

  final String markdown;
  final bool compact;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final data = markdown.trim();
    if (data.isEmpty) return const SizedBox.shrink();

    return MarkdownBody(
      data: data,
      selectable: selectable && !compact,
      softLineBreak: true,
      styleSheet: _robotMdStyle(compact: compact),
      onTapLink: (text, href, title) {
        if (href == null || href.trim().isEmpty) return;
        final uri = Uri.tryParse(href.trim());
        if (uri == null) return;
        launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

/// 列表卡片预览：去掉常见 Markdown 标记，避免露出 `**`。
String robotPlainPreview(String markdown, {int maxChars = 80}) {
  var s = markdown.trim();
  if (s.isEmpty) return '';
  s = s
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'`([^`]*)`'), r'$1')
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'__([^_]+)__'), r'$1')
      .replaceAll(RegExp(r'[*_]'), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length <= maxChars) return s;
  return '${s.substring(0, maxChars)}…';
}
