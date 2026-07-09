import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../nova/nova_deliverable.dart';

/// 会议摘要 Markdown 渲染（尽量与 NOVA 展示兼容）。
class MeetingMinutesMarkdown extends StatelessWidget {
  const MeetingMinutesMarkdown({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeNovaMarkdownLayout(markdown.trim());
    if (normalized.isEmpty) return const SizedBox.shrink();

    final style = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: DunesTypography.sans(
        fontSize: 14,
        color: DunesColors.text2,
        height: 1.7,
      ),
      h1: DunesTypography.sans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: DunesColors.text,
        height: 1.4,
      ),
      h2: DunesTypography.sans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: DunesColors.text,
        height: 1.4,
      ),
      h3: DunesTypography.sans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: DunesColors.text2,
        height: 1.4,
      ),
      strong: const TextStyle(
        fontWeight: FontWeight.w600,
        color: DunesColors.text,
      ),
      em: const TextStyle(fontStyle: FontStyle.italic),
      code: DunesTypography.mono(fontSize: 12, color: DunesColors.text),
      listBullet: DunesTypography.sans(
        fontSize: 14,
        color: DunesColors.text3,
        height: 1.7,
      ),
      blockquote: DunesTypography.sans(
        fontSize: 13,
        color: DunesColors.text3,
        height: 1.6,
      ),
      a: const TextStyle(
        color: DunesColors.accentDeep,
        decoration: TextDecoration.underline,
      ),
    );

    return MarkdownBody(
      data: normalized,
      selectable: true,
      softLineBreak: true,
      styleSheet: style,
      onTapLink: (text, href, title) {
        if (href == null || href.trim().isEmpty) return;
        final uri = Uri.tryParse(href.trim());
        if (uri == null) return;
        if (text.isEmpty && title.isEmpty) return;
        launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}
