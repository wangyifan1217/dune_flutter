import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'nova_deliverable.dart';
import 'nova_media.dart';

/// 云枢 AI 回复富文本渲染（对齐 WebView `renderNovaBodyHtml`）。
class NovaMarkdownBody extends StatelessWidget {
  const NovaMarkdownBody({
    super.key,
    required this.text,
    this.streaming = false,
    this.mediaResolver,
  });

  final String text;
  final bool streaming;
  final NovaMediaResolver? mediaResolver;

  @override
  Widget build(BuildContext context) {
    final prep = prepareNovaAssistantBody(text);
    var raw = prep.raw;
    if (raw.isEmpty && prep.toolRaw.isNotEmpty) {
      raw = stripNovaToolCallLeak(prep.toolRaw);
    }
    if (raw.isEmpty) {
      return streaming
          ? Text('…', style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3))
          : const SizedBox.shrink();
    }

    final shownNames = <String>{};
    final shownUrls = <String>{};
    final widgets = <Widget>[];

    if (raw.contains('```')) {
      for (final part in splitNovaMarkdownFences(raw)) {
        if (part.isCode) {
          widgets.add(NovaCodeBlock(
            language: part.lang,
            code: part.body,
            partial: streaming && part.open,
          ));
        } else {
          widgets.addAll(_renderInlineSegment(context, part.body, shownNames, shownUrls));
        }
      }
    } else {
      widgets.addAll(_renderInlineSegment(context, raw, shownNames, shownUrls));
    }

    for (final f in collectNovaExtraFiles(prep.toolRaw.isNotEmpty ? prep.toolRaw : text, shownNames, shownUrls)) {
      widgets.add(_deliverableCard(context, f, shownNames, shownUrls));
    }

    if (widgets.isEmpty) {
      return streaming
          ? Text('…', style: DunesTypography.sans(fontSize: 13, color: DunesColors.text3))
          : const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  List<Widget> _renderInlineSegment(
    BuildContext context,
    String body,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    var raw = body.replaceAll(RegExp(r'\]\s*\n+\s*\('), '](');
    if (raw.trim().isEmpty) return const [];

    var file = tryParseHermesFileJson(raw) ?? tryParseMarkdownFileLink(raw);
    var rest = '';
    if (file == null) {
      final block = RegExp(r'\{[\s\S]*"(?:download_url|chat_link|display_filename)"[\s\S]*\}').firstMatch(raw);
      if (block != null) {
        file = tryParseHermesFileJson(block.group(0)!);
        rest = raw.replaceFirst(block.group(0)!, '').trim();
      }
    }
    if (file != null && file.url.isNotEmpty) {
      final widgets = <Widget>[];
      if (rest.isNotEmpty) widgets.addAll(_renderInlineSegment(context, rest, shownNames, shownUrls));
      widgets.add(_deliverableCard(context, file.copyWithExt(), shownNames, shownUrls));
      return widgets;
    }

    final linkRe = RegExp(r'\[([^\]]+)\]\((https?:[^)\s]+)\)', caseSensitive: false);
    if (linkRe.hasMatch(raw)) {
      final widgets = <Widget>[];
      var last = 0;
      for (final m in linkRe.allMatches(raw)) {
        if (m.start > last) {
          widgets.addAll(_renderPlainOrBlock(context, raw.substring(last, m.start), shownNames, shownUrls));
        }
        widgets.add(_markdownLinkCard(context, m.group(1)!, m.group(2)!, shownNames, shownUrls));
        last = m.end;
      }
      if (last < raw.length) {
        widgets.addAll(_renderPlainOrBlock(context, raw.substring(last), shownNames, shownUrls));
      }
      return widgets;
    }

    final bareRe = RegExp(
      r'\((https?:\/\/[^)\s]+\.(?:jpe?g|png|gif|webp|svg)(?:\?[^)\s]*)?)\)',
      caseSensitive: false,
    );
    if (bareRe.hasMatch(raw)) {
      final widgets = <Widget>[];
      var last = 0;
      for (final m in bareRe.allMatches(raw)) {
        if (m.start > last) {
          widgets.addAll(_renderPlainOrBlock(context, raw.substring(last, m.start), shownNames, shownUrls));
        }
        final u = m.group(1)!;
        var nm = '图片';
        try {
          nm = Uri.decodeComponent(u.split('/').last.split('?').first);
        } catch (_) {}
        widgets.add(_imageCard(context, NovaDeliverableItem(url: u, name: nm, ext: novaFileExt(u)), shownNames, shownUrls));
        last = m.end;
      }
      if (last < raw.length) {
        widgets.addAll(_renderPlainOrBlock(context, raw.substring(last), shownNames, shownUrls));
      }
      return widgets;
    }

    final withFiles = _renderTextWithGeneratedFiles(context, raw, shownNames, shownUrls);
    if (withFiles.isNotEmpty) return withFiles;

    return _renderPlainOrBlock(context, raw, shownNames, shownUrls);
  }

  List<Widget> _renderTextWithGeneratedFiles(
    BuildContext context,
    String raw,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    if (raw.trim().isEmpty || extractNovaMarkdownFileLinks(raw).isNotEmpty) return const [];
    final re = novaGeneratedFilePathRe();
    if (!re.hasMatch(raw)) return const [];

    final widgets = <Widget>[];
    var last = 0;
    for (final m in re.allMatches(raw)) {
      if (m.start > last) {
        widgets.add(_NovaMarkdownInline(text: raw.substring(last, m.start)));
      }
      final path = m.group(1)!;
      final name = path.split('/').last;
      widgets.add(_fileCard(
        context,
        NovaDeliverableItem(agentPath: path, path: path, name: name, ext: novaFileExt(name)),
        shownNames,
        shownUrls,
      ));
      last = m.end;
    }
    if (last < raw.length) {
      widgets.add(_NovaMarkdownInline(text: raw.substring(last)));
    }
    return widgets;
  }

  List<Widget> _renderPlainOrBlock(
    BuildContext context,
    String raw,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    if (RegExp(r'^#{1,3}\s', multiLine: true).hasMatch(raw) ||
        RegExp(r'^[-*•]\s', multiLine: true).hasMatch(raw)) {
      return [_NovaMarkdownBlock(text: raw, onImage: (item) => _imageCard(context, item, shownNames, shownUrls))];
    }
    return [_NovaMarkdownInline(
      text: raw,
      onImage: (item) => _imageCard(context, item, shownNames, shownUrls),
      onFileLink: (label, url) => _markdownLinkCard(context, label, url, shownNames, shownUrls),
    )];
  }

  Widget _markdownLinkCard(
    BuildContext context,
    String label,
    String url,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    final item = NovaDeliverableItem(
      url: url,
      name: label,
      ext: novaFileExt(label).isNotEmpty ? novaFileExt(label) : novaFileExt(url.split('?').first),
    );
    if (novaIsImageFile(item)) return _imageCard(context, item, shownNames, shownUrls);
    if (novaShouldRenderLinkAsFileCard(label, url)) {
      return _fileCard(context, item, shownNames, shownUrls);
    }
    return _NovaMarkdownInline(text: '[$label]($url)', linkOnly: true);
  }

  Widget _deliverableCard(
    BuildContext context,
    NovaDeliverableItem file,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    if (novaIsImageFile(file)) return _imageCard(context, file, shownNames, shownUrls);
    return _fileCard(context, file, shownNames, shownUrls);
  }

  Widget _imageCard(
    BuildContext context,
    NovaDeliverableItem file,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    shownNames.add(file.name);
    if (file.url.isNotEmpty) shownUrls.add(file.url);
    if (mediaResolver == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(file.name, style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NovaC4ImageCard(
        resolver: mediaResolver!,
        url: file.url,
        fileName: sanitizeNovaDeliverableName(file.name),
        agentPath: file.effectiveAgentPath,
        agentPathCandidates: file.agentPathCandidates,
      ),
    );
  }

  Widget _fileCard(
    BuildContext context,
    NovaDeliverableItem file,
    Set<String> shownNames,
    Set<String> shownUrls,
  ) {
    shownNames.add(file.name);
    if (file.url.isNotEmpty) shownUrls.add(file.url);
    if (mediaResolver == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(file.name, style: DunesTypography.sans(fontSize: 13, color: DunesColors.text2)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NovaC4DeliverableFileCard(
        resolver: mediaResolver!,
        file: file,
      ),
    );
  }
}

/// 代码块（对齐 WebView `.nova-code-block`，含复制按钮）。
class NovaCodeBlock extends StatelessWidget {
  const NovaCodeBlock({
    super.key,
    required this.language,
    required this.code,
    this.partial = false,
  });

  final String language;
  final String code;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final lang = language.trim().isEmpty ? 'text' : language.trim();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: partial ? const Color(0x592F5D62) : const Color(0x1F0F172A),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x140F172A), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: const BoxDecoration(
              color: Color(0x0AFFFFFF),
              border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
            ),
            child: Row(
              children: [
                Text(
                  lang.toUpperCase(),
                  style: DunesTypography.mono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0x8CFFFFFF),
                    letterSpacing: 0.04 * 11,
                  ),
                ),
                const Spacer(),
                Material(
                  color: const Color(0x0FFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        showDunesToast(context, '已复制', duration: const Duration(milliseconds: 1200));
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded, size: 14, color: Color(0xD9FFFFFF)),
                          const SizedBox(width: 4),
                          Text(
                            '复制',
                            style: DunesTypography.sans(fontSize: 11, color: const Color(0xD9FFFFFF)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(
              code + (partial ? '▍' : ''),
              style: DunesTypography.mono(fontSize: 12, color: const Color(0xFFE8EEED), height: 1.5),
            ),
          ),
          if (partial)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '代码生成中…',
                style: DunesTypography.sans(fontSize: 11, color: const Color(0x8CFFFFFF)),
              ),
            ),
        ],
      ),
    );
  }
}

class _NovaMarkdownBlock extends StatelessWidget {
  const _NovaMarkdownBlock({
    required this.text,
    required this.onImage,
  });

  final String text;
  final Widget Function(NovaDeliverableItem item) onImage;

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeNovaMarkdownLayout(text);
    final lines = normalized.split('\n');
    final children = <Widget>[];
    var listItems = <Widget>[];

    void flushList() {
      if (listItems.isEmpty) return;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: listItems,
        ),
      ));
      listItems = [];
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flushList();
        continue;
      }
      final hm = RegExp(r'^#{1,3}\s*(.+)$').firstMatch(trimmed);
      if (hm != null) {
        flushList();
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
          child: _NovaMarkdownInline(text: hm.group(1)!, heading: true, onImage: onImage),
        ));
        continue;
      }
      final lm = RegExp(r'^[-*•]\s+(.+)$').firstMatch(trimmed);
      if (lm != null) {
        listItems.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 13, color: DunesColors.text, height: 1.6)),
              Expanded(child: _NovaMarkdownInline(text: lm.group(1)!, onImage: onImage)),
            ],
          ),
        ));
        continue;
      }
      flushList();
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _NovaMarkdownInline(text: trimmed, onImage: onImage),
      ));
    }
    flushList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _NovaMarkdownInline extends StatelessWidget {
  const _NovaMarkdownInline({
    required this.text,
    this.heading = false,
    this.linkOnly = false,
    this.onImage,
    this.onFileLink,
  });

  final String text;
  final bool heading;
  final bool linkOnly;
  final Widget Function(NovaDeliverableItem item)? onImage;
  final Widget Function(String label, String url)? onFileLink;

  @override
  Widget build(BuildContext context) {
    if (onImage != null && RegExp(r'!\[[^\]]*\]\(https?:', caseSensitive: false).hasMatch(text)) {
      return _buildWithImageWidgets(context);
    }
    final spans = <InlineSpan>[];
    _parseInline(text, spans, context);
    return SelectableText.rich(
      TextSpan(
        style: DunesTypography.sans(
          fontSize: heading ? 15 : 13,
          fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
          color: DunesColors.text,
          height: heading ? 1.45 : 1.65,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildWithImageWidgets(BuildContext context) {
    final widgets = <Widget>[];
    final imgRe = RegExp(r'!\[([^\]]*)\]\((https?:[^)\s]+)\)', caseSensitive: false);
    var idx = 0;
    for (final m in imgRe.allMatches(text)) {
      if (m.start > idx) {
        widgets.add(_NovaMarkdownInline(text: text.substring(idx, m.start)));
      }
      var nm = m.group(1)?.trim() ?? '';
      if (nm.isEmpty) {
        try {
          nm = Uri.decodeComponent(m.group(2)!.split('/').last.split('?').first);
        } catch (_) {
          nm = '图片';
        }
      }
      widgets.add(onImage!(NovaDeliverableItem(url: m.group(2)!, name: nm, ext: novaFileExt(m.group(2)!))));
      idx = m.end;
    }
    if (idx < text.length) {
      widgets.add(_NovaMarkdownInline(text: text.substring(idx)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  void _parseInline(String input, List<InlineSpan> out, BuildContext context) {
    final re = RegExp(
      r'(\*\*.+?\*\*|\*.+?\*|`[^`\n]+`|\[([^\]]+)\]\((https?:[^)\s]+)\)|!\[([^\]]*)\]\((https?:[^)\s]+)\))',
    );
    var idx = 0;
    for (final m in re.allMatches(input)) {
      if (m.start > idx) {
        out.add(TextSpan(text: input.substring(idx, m.start)));
      }
      final token = m.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        out.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700, color: DunesColors.accentDeep),
        ));
      } else if (token.startsWith('*') && token.endsWith('*') && !token.startsWith('**')) {
        out.add(TextSpan(text: token.substring(1, token.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else if (token.startsWith('`') && token.endsWith('`')) {
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: const Color(0x142F5D62),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x1F2F5D62)),
            ),
            child: Text(
              token.substring(1, token.length - 1),
              style: DunesTypography.mono(fontSize: 11.5, color: DunesColors.accentDeep),
            ),
          ),
        ));
      } else if (token.startsWith('![')) {
        // 图片由上层 onImage 处理；此处跳过
        final url = m.group(5);
        if (url != null && onImage == null) {
          out.add(TextSpan(
            text: url,
            style: const TextStyle(color: DunesColors.accentDeep, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
          ));
        }
      } else if (token.startsWith('[')) {
        final label = m.group(2)!;
        final url = m.group(3)!;
        if (onFileLink != null && (novaShouldRenderLinkAsFileCard(label, url) || novaIsImageExt(novaFileExt(url)))) {
          // 由 block 层处理
          out.add(TextSpan(text: label));
        } else {
          out.add(TextSpan(
            text: label,
            style: const TextStyle(color: DunesColors.accentDeep, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
          ));
        }
      } else {
        out.add(TextSpan(text: token));
      }
      idx = m.end;
    }
    if (idx < input.length) {
      final tail = input.substring(idx);
      out.add(TextSpan(text: tail.replaceAll('\n', linkOnly ? '' : '\n')));
    }
  }
}
