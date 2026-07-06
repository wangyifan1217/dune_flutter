import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

/// 会议摘要 Markdown 渲染（对齐 admin-web `MeetingMinutesContent`）。
class MeetingMinutesMarkdown extends StatelessWidget {
  const MeetingMinutesMarkdown({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseMarkdownBlocks(markdown.trim());
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          _BlockView(block: blocks[i], index: i),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Block model & parser
// ---------------------------------------------------------------------------

sealed class _Block {}

class _HeadingBlock extends _Block {
  _HeadingBlock({required this.level, required this.text});
  final int level;
  final String text;
}

class _HrBlock extends _Block {}

class _QuoteBlock extends _Block {
  _QuoteBlock(this.lines);
  final List<String> lines;
}

class _UlBlock extends _Block {
  _UlBlock(this.items);
  final List<String> items;
}

class _OlBlock extends _Block {
  _OlBlock(this.items);
  final List<String> items;
}

class _ParagraphBlock extends _Block {
  _ParagraphBlock(this.text);
  final String text;
}

List<_Block> _parseMarkdownBlocks(String source) {
  if (source.isEmpty) return const [];

  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_Block>[];
  final ulBuf = <String>[];
  final olBuf = <String>[];

  void flushList(List<String> buf, bool ordered) {
    if (buf.isEmpty) return;
    blocks.add(ordered ? _OlBlock([...buf]) : _UlBlock([...buf]));
    buf.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushList(ulBuf, false);
      flushList(olBuf, true);
      i += 1;
      continue;
    }

    if (RegExp(r'^---+$').hasMatch(trimmed)) {
      flushList(ulBuf, false);
      flushList(olBuf, true);
      blocks.add(_HrBlock());
      i += 1;
      continue;
    }

    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
    if (heading != null) {
      flushList(ulBuf, false);
      flushList(olBuf, true);
      blocks.add(_HeadingBlock(
        level: heading.group(1)!.length,
        text: heading.group(2)!.trim(),
      ));
      i += 1;
      continue;
    }

    if (trimmed.startsWith('>')) {
      flushList(ulBuf, false);
      flushList(olBuf, true);
      final quoteLines = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quoteLines.add(
          lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''),
        );
        i += 1;
      }
      blocks.add(_QuoteBlock(quoteLines));
      continue;
    }

    final ulMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
    if (ulMatch != null) {
      flushList(olBuf, true);
      ulBuf.add(ulMatch.group(1)!);
      i += 1;
      continue;
    }

    final olMatch = RegExp(r'^\d+\.\s+(.+)$').firstMatch(trimmed);
    if (olMatch != null) {
      flushList(ulBuf, false);
      olBuf.add(olMatch.group(1)!);
      i += 1;
      continue;
    }

    flushList(ulBuf, false);
    flushList(olBuf, true);
    final paraLines = <String>[trimmed];
    i += 1;
    while (i < lines.length) {
      final next = lines[i].trim();
      if (next.isEmpty ||
          next.startsWith('#') ||
          next.startsWith('>') ||
          RegExp(r'^---+$').hasMatch(next) ||
          RegExp(r'^[-*]\s+').hasMatch(next) ||
          RegExp(r'^\d+\.\s+').hasMatch(next)) {
        break;
      }
      paraLines.add(next);
      i += 1;
    }
    blocks.add(_ParagraphBlock(paraLines.join(' ')));
  }

  flushList(ulBuf, false);
  flushList(olBuf, true);
  return blocks;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.index});

  final _Block block;
  final int index;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      _HeadingBlock(:final level, :final text) => _buildHeading(level, text),
      _HrBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: DunesColors.borderSoft),
        ),
      _QuoteBlock(:final lines) => _buildQuote(lines),
      _UlBlock(:final items) => _buildList(items, ordered: false),
      _OlBlock(:final items) => _buildList(items, ordered: true),
      _ParagraphBlock(:final text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _InlineText(text, style: _bodyStyle),
        ),
    };
  }

  static final _bodyStyle = DunesTypography.sans(
    fontSize: 14,
    color: DunesColors.text2,
    height: 1.7,
  );

  Widget _buildHeading(int level, String text) {
    final (top, bottom, fontSize, color, border) = switch (level) {
      1 => (0.0, 12.0, 18.0, DunesColors.text, false),
      2 => (20.0, 8.0, 15.0, DunesColors.text, true),
      _ => (14.0, 6.0, 14.0, DunesColors.text2, false),
    };

    final style = DunesTypography.sans(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: color,
      height: 1.4,
    );

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InlineText(text, style: style),
          if (border)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Divider(height: 1, color: DunesColors.bgSoft),
            ),
        ],
      ),
    );
  }

  Widget _buildQuote(List<String> lines) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DunesColors.accent.withValues(alpha: 0.06),
            const Color(0xFF7E64BD).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DunesColors.accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var li = 0; li < lines.length; li++)
            Padding(
              padding: EdgeInsets.only(bottom: li < lines.length - 1 ? 4 : 0),
              child: _InlineText(
                lines[li],
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<String> items, {required bool ordered}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var li = 0; li < items.length; li++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      ordered ? '${li + 1}.' : '•',
                      style: DunesTypography.sans(
                        fontSize: 14,
                        color: DunesColors.text3,
                        height: 1.7,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _InlineText(items[li], style: _bodyStyle),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineText extends StatelessWidget {
  const _InlineText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = text.split(RegExp(r'(\*\*[^*]+\*\*)')).where((p) => p.isNotEmpty);
    final spans = <TextSpan>[];
    for (final part in parts) {
      if (part.startsWith('**') && part.endsWith('**') && part.length > 4) {
        spans.add(TextSpan(
          text: part.substring(2, part.length - 2),
          style: style.copyWith(
            fontWeight: FontWeight.w600,
            color: DunesColors.text,
          ),
        ));
      } else {
        spans.add(TextSpan(text: part, style: style));
      }
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}
