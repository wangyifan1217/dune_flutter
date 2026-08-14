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
    // 按内容确定列宽；flutter_markdown 会为超出气泡宽度的表格提供横向滚动，
    // 避免移动端多列表格被 Flex 压缩后出现中文逐字换行。
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
    this.fitToContent = false,
  });

  final String markdown;
  final bool compact;
  final bool selectable;

  /// 为 true 时按内容自然撑开（宽表交给外层横向滚动），不钉死父宽。
  final bool fitToContent;

  @override
  Widget build(BuildContext context) {
    final data = markdown.trim();
    if (data.isEmpty) return const SizedBox.shrink();

    MarkdownBody buildBody({required double imageMaxWidth, required bool fit}) {
      return MarkdownBody(
        data: data,
        selectable: selectable && !compact,
        softLineBreak: true,
        fitContent: fit,
        styleSheet: _robotMdStyle(compact: compact),
        sizedImageBuilder: (config) => _RobotMdImage(
          uri: config.uri,
          alt: config.alt,
          width: config.width,
          height: config.height,
          maxWidth: imageMaxWidth,
        ),
        onTapLink: (text, href, title) {
          if (href == null || href.trim().isEmpty) return;
          final uri = Uri.tryParse(href.trim());
          if (uri == null) return;
          launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      );
    }

    if (fitToContent) return buildBody(imageMaxWidth: 480, fit: true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.sizeOf(context).width;
        // 无界约束时（偶发首帧）回落到屏宽，避免宽表按「无限宽」量测把整页撑大。
        final maxW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : (screenW - 72).clamp(200.0, screenW);
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: SizedBox(
            width: maxW,
            child: buildBody(imageMaxWidth: maxW, fit: false),
          ),
        );
      },
    );
  }
}

class _RobotMdImage extends StatelessWidget {
  const _RobotMdImage({
    required this.uri,
    required this.maxWidth,
    this.alt,
    this.width,
    this.height,
  });

  final Uri uri;
  final String? alt;
  final double? width;
  final double? height;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final targetW = () {
      final w = width;
      if (w != null && w.isFinite && w > 0) {
        return w > maxWidth ? maxWidth : w;
      }
      return maxWidth;
    }();
    final provider = switch (uri.scheme) {
      'http' || 'https' => NetworkImage(uri.toString()),
      'data' => null,
      _ => NetworkImage(uri.toString()),
    };
    if (provider == null) {
      return Text(
        alt?.trim().isNotEmpty == true ? alt!.trim() : '[图片]',
        style: const TextStyle(fontSize: 12, color: RobotTheme.text3),
      );
    }
    return Image(
      image: provider,
      width: targetW,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Text(
        alt?.trim().isNotEmpty == true ? alt!.trim() : '[图片加载失败]',
        style: const TextStyle(fontSize: 12, color: RobotTheme.text3),
      ),
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
