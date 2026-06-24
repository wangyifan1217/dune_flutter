import 'dart:convert';

import 'package:flutter/material.dart';

import 'nova_stream_parser.dart';

/// 云枢回复中的可交付物（图片 / 文件），对齐 WebView `renderNovaImageCard` / `renderNovaFileCard`。
class NovaDeliverableItem {
  const NovaDeliverableItem({
    this.url = '',
    required this.name,
    this.ext = '',
    this.agentPath = '',
    this.path = '',
    this.agentPathCandidates = const <String>[],
  });

  final String url;
  final String name;
  final String ext;
  final String agentPath;
  final String path;
  final List<String> agentPathCandidates;

  String get effectiveAgentPath => agentPath.isNotEmpty ? agentPath : path;

  NovaDeliverableItem copyWithExt() {
    if (ext.isNotEmpty) return this;
    final e = novaFileExt(name).isNotEmpty ? novaFileExt(name) : novaFileExt(url.split('?').first);
    return NovaDeliverableItem(
      url: url,
      name: name,
      ext: e,
      agentPath: agentPath,
      path: path,
      agentPathCandidates: agentPathCandidates,
    );
  }
}

String sanitizeNovaDeliverableName(String name) {
  var s = name.trim();
  s = s.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1)!);
  s = s.replaceAll('*', '');
  return s.trim().isEmpty ? 'image' : s.trim();
}

bool novaImageUrlNeedsAuthFetch(String url) {
  final u = url.trim();
  if (u.isEmpty) return false;
  return RegExp(r'/v1/files/download', caseSensitive: false).hasMatch(u);
}

String normalizeNovaBodyText(String text) {
  return text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').trim();
}

String sanitizeNovaBody(String text) {
  var s = normalizeNovaBodyText(text);
  s = s.replaceFirst(RegExp(r'^助手\s*[·•]\s*', unicode: true), '');
  s = s.replaceFirst(RegExp(r'^助手\s+', unicode: true), '');
  return s.trim();
}

String stripNovaToolCallLeak(String text) {
  if (text.isEmpty) return '';
  var s = text;
  s = s.replaceAll(RegExp(r'<\s*tool_calls[\s\S]*?<\s*/\s*tool_calls\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<\s*tool_call[\s\S]*?<\s*/\s*tool_call\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<\s*invoke[\s\S]*?<\s*/\s*invoke\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<\s*parameter[\s\S]*?<\s*/\s*parameter\s*>', caseSensitive: false), '');
  s = s.replaceAll(
    RegExp(r'\btool_calls\s*>[\s\S]*?(?:>\s*/\s*tool_calls\s*>|>\s*tool_calls\s*>)', caseSensitive: false),
    '',
  );
  s = s.replaceAll(
    RegExp(
      r'''\binvoke\s*name\s*=\s*["'][^"']+["'][\s\S]*?(?:>\s*/\s*invoke\s*>|>\s*invoke\s*>)''',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(
    RegExp(
      r'''(?:parameter\s*name\s*=|parametername\s*=)\s*["'][^"']+["'][\s\S]*?>\s*parameter\s*>''',
      caseSensitive: false,
    ),
    '',
  );
  s = s.replaceAll(RegExp(r'<\/?tool_calls\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<\/?invoke\s*>', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'<\/?parameter\s*>', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

({String raw, String toolRaw}) prepareNovaAssistantBody(String body) {
  final split = splitNovaReasoningReply(body, finalPass: true);
  final reply = stripHermesProgressLines(sanitizeNovaBody(split.reply.isNotEmpty ? split.reply : body));
  if (reply.isEmpty) return (raw: '', toolRaw: '');
  return (raw: stripNovaToolCallLeak(reply), toolRaw: reply);
}

String novaFileExt(String name) {
  final path = name.split('?').first;
  final i = path.lastIndexOf('.');
  return i >= 0 ? path.substring(i + 1).toLowerCase() : '';
}

bool novaIsImageExt(String ext) {
  return RegExp(r'^(jpe?g|png|gif|webp|svg|bmp)$', caseSensitive: false).hasMatch(ext);
}

bool novaIsDeliverableFileExt(String ext) {
  return RegExp(r'^(md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z|pptx?)$', caseSensitive: false)
      .hasMatch(ext);
}

bool novaIsImageFile(NovaDeliverableItem file) {
  if (file.url.isEmpty) return false;
  return novaIsImageExt(file.ext) || novaIsImageExt(novaFileExt(file.url));
}

bool novaShouldRenderLinkAsFileCard(String label, String url) {
  if (!RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) return false;
  final ext = novaFileExt(label).isNotEmpty ? novaFileExt(label) : novaFileExt(url.split('?').first);
  return ext.isNotEmpty && !novaIsImageExt(ext) && novaIsDeliverableFileExt(ext);
}

IconData novaFileIconData(String ext) {
  switch (ext.toLowerCase()) {
    case 'html':
    case 'htm':
      return Icons.code;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
      return Icons.table_chart_outlined;
    case 'zip':
    case 'rar':
    case '7z':
      return Icons.folder_zip_outlined;
    case 'md':
    case 'txt':
      return Icons.article_outlined;
    default:
      if (novaIsImageExt(ext)) return Icons.photo_outlined;
      return Icons.insert_drive_file_outlined;
  }
}

String _extractUrlFromMarkdownLink(String link) {
  final m = RegExp(r'\((https?:[^)\s]+)\)').firstMatch(link);
  return m?.group(1)?.trim() ?? '';
}

String _extractNameFromMarkdownLink(String link) {
  final m = RegExp(r'^\[([^\]]+)\]').firstMatch(link.trim());
  return m?.group(1)?.trim() ?? '';
}

NovaDeliverableItem? tryParseHermesFileJson(String text) {
  final raw = normalizeNovaBodyText(text);
  if (raw.isEmpty) return null;

  NovaDeliverableItem? fromObj(Map<String, dynamic> o) {
    var url = (o['download_url'] ?? o['downloadUrl'] ?? '').toString().trim();
    if (url.isEmpty) {
      url = _extractUrlFromMarkdownLink((o['chat_link'] ?? o['chatLink'] ?? '').toString());
    }
    var name = (o['display_filename'] ?? o['displayFilename'] ?? '').toString().trim();
    if (name.isEmpty) {
      name = _extractNameFromMarkdownLink((o['chat_link'] ?? o['chatLink'] ?? '').toString());
    }
    if (url.isEmpty && name.isEmpty) return null;
    if (name.isEmpty && url.isNotEmpty) {
      try {
        name = Uri.decodeComponent(url.split('/').last.split('?').first);
      } catch (_) {
        name = '文件';
      }
    }
    name = sanitizeNovaDeliverableName(name.isEmpty ? '文件' : name);
    return NovaDeliverableItem(url: url, name: name, ext: novaFileExt(name));
  }

  try {
    final direct = fromObj(jsonDecode(raw) as Map<String, dynamic>);
    if (direct != null && direct.url.isNotEmpty) return direct;
  } catch (_) {}

  final block = RegExp(r'\{[\s\S]*"(?:download_url|chat_link|display_filename)"[\s\S]*\}').firstMatch(raw);
  if (block != null) {
    try {
      final inner = fromObj(jsonDecode(block.group(0)!) as Map<String, dynamic>);
      if (inner != null && inner.url.isNotEmpty) return inner;
    } catch (_) {}
  }
  return null;
}

NovaDeliverableItem? tryParseMarkdownFileLink(String text) {
  final raw = normalizeNovaBodyText(text);
  final m = RegExp(r'^\[([^\]]+)\]\((https?:[^)\s]+)\)\s*$').firstMatch(raw);
  if (m == null) return null;
  return NovaDeliverableItem(
    url: m.group(2)!,
    name: m.group(1)!,
    ext: novaFileExt(m.group(1)!).isNotEmpty ? novaFileExt(m.group(1)!) : novaFileExt(m.group(2)!),
  );
}

const _novaGenFileExt =
    r'md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z|png|jpe?g|gif|webp|svg|pptx?';

RegExp novaGeneratedFilePathRe() {
  return RegExp(
    r'((?:/[\w.-]+)+\.(?:' + _novaGenFileExt + r'))',
    caseSensitive: false,
  );
}

List<NovaDeliverableItem> extractNovaMarkdownFileLinks(String text) {
  final files = <NovaDeliverableItem>[];
  final seen = <String>{};
  final re = RegExp(r'\[([^\]]+)\]\((https?:[^)\s]+)\)', caseSensitive: false);
  for (final m in re.allMatches(text)) {
    final name = m.group(1)?.trim() ?? '文件';
    final url = m.group(2)?.trim() ?? '';
    if (url.isEmpty) continue;
    final ext = novaFileExt(name).isNotEmpty ? novaFileExt(name) : novaFileExt(url.split('?').first);
    if (ext.isEmpty || novaIsImageExt(ext) || !novaIsDeliverableFileExt(ext)) continue;
    if (seen.contains(url)) continue;
    seen.add(url);
    files.add(NovaDeliverableItem(url: url, name: name, ext: ext));
  }
  return files;
}

List<NovaDeliverableItem> extractNovaToolCallFiles(String text) {
  if (!RegExp(r'tool_calls|invoke|write_file|parametername', caseSensitive: false).hasMatch(text)) {
    return const [];
  }
  final files = <NovaDeliverableItem>[];
  final seen = <String>{};
  final re = RegExp(
    r'''(?:parameter\s*name\s*=\s*["']path["']|parametername\s*=\s*["']path["']|["']path["'][^>]*>)\s*(\/[\w./-]+\.\w+)''',
    caseSensitive: false,
  );
  for (final m in re.allMatches(text)) {
    final path = m.group(1)?.trim() ?? '';
    if (path.isEmpty || seen.contains(path)) continue;
    seen.add(path);
    final name = path.split('/').last;
    files.add(NovaDeliverableItem(path: path, agentPath: path, name: name, ext: novaFileExt(name)));
  }
  return files;
}

List<NovaDeliverableItem> extractNovaGeneratedFiles(String text) {
  final raw = normalizeNovaBodyText(text);
  if (raw.isEmpty) return const [];
  if (extractNovaMarkdownFileLinks(raw).isNotEmpty) return const [];
  final files = <NovaDeliverableItem>[];
  final seen = <String>{};
  for (final m in novaGeneratedFilePathRe().allMatches(raw)) {
    final path = m.group(1)!;
    if (seen.contains(path)) continue;
    seen.add(path);
    final name = path.split('/').last;
    files.add(NovaDeliverableItem(path: path, agentPath: path, name: name, ext: novaFileExt(name)));
  }
  return files;
}

List<String> guessNovaAgentPaths(String name) {
  name = name.trim();
  if (name.isEmpty) return const [];
  final base = name.split('/').last;
  final out = <String>[];
  for (final p in [name, base, '/tmp/$base', '/workspace/$base', '/opt/data/$base', '/root/$base']) {
    if (p.isNotEmpty && !out.contains(p)) out.add(p);
  }
  return out;
}

List<NovaDeliverableItem> extractNovaNamedDownloadFiles(String text) {
  final raw = normalizeNovaBodyText(text);
  if (raw.isEmpty) return const [];
  if (!RegExp(r'(?:可下载|下载链接|点击下载|Markdown文件|markdown文件|📎|下载\s*链接)', caseSensitive: false)
      .hasMatch(raw)) {
    return const [];
  }
  if (tryParseHermesFileJson(raw) != null || extractNovaMarkdownFileLinks(raw).isNotEmpty) {
    return const [];
  }
  final files = <NovaDeliverableItem>[];
  final seen = <String>{};
  final re = RegExp(
    r'([\w\u4e00-\u9fff._-]+\.(?:md|txt|html?|pdf|docx?|xlsx?|csv|json|xml|yaml|yml|zip|rar|7z))',
    caseSensitive: false,
  );
  for (final m in re.allMatches(raw)) {
    final name = m.group(1)?.trim() ?? '';
    if (name.isEmpty || seen.contains(name)) continue;
    if (!novaIsDeliverableFileExt(novaFileExt(name))) continue;
    seen.add(name);
    final paths = guessNovaAgentPaths(name);
    files.add(NovaDeliverableItem(
      name: name,
      ext: novaFileExt(name),
      agentPath: paths.isNotEmpty ? paths.first : name,
      agentPathCandidates: paths,
    ));
  }
  return files;
}

List<NovaDeliverableItem> collectNovaExtraFiles(
  String raw,
  Set<String> shownNames,
  Set<String> shownUrls,
) {
  final markdownFiles = extractNovaMarkdownFileLinks(raw);
  final mdNames = {for (final f in markdownFiles) f.name: true};
  final all = <NovaDeliverableItem>[
    ...markdownFiles,
    ...extractNovaToolCallFiles(raw),
    ...extractNovaGeneratedFiles(raw),
    ...extractNovaNamedDownloadFiles(raw),
  ];
  final hasDownloadIntent = RegExp(
    r'(?:可下载|下载链接|点击下载|Markdown文件|markdown文件|📎|下载\s*链接|附件|\.md\)|\.pdf\))',
    caseSensitive: false,
  ).hasMatch(raw);
  final out = <NovaDeliverableItem>[];
  final seenUrl = <String>{};
  final seenAgent = <String>{};
  for (final f in all) {
    if (f.url.isNotEmpty) {
      if (seenUrl.contains(f.url) || shownUrls.contains(f.url)) continue;
      seenUrl.add(f.url);
    } else {
      final agentKey = f.effectiveAgentPath;
      if (agentKey.isEmpty || seenAgent.contains(agentKey)) continue;
      if (mdNames.containsKey(f.name)) continue;
      if (!hasDownloadIntent && f.url.isEmpty) continue;
      seenAgent.add(agentKey);
    }
    if (shownNames.contains(f.name)) continue;
    out.add(f);
  }
  return out;
}

String normalizeNovaMarkdownLayout(String text) {
  var s = text;
  s = s.replaceAll(
    RegExp(r'(\.(?:md|txt|html?|pdf|docx?|xlsx?|csv|json|yaml|yml|zip|rar|7z))(#\s*)', caseSensitive: false),
    r'$1\n\n$2',
  );
  s = s.replaceAllMapped(RegExp(r'([。！？!?.])(#\s*[^\n#]+)'), (m) => '${m.group(1)}\n\n${m.group(2)}');
  s = s.replaceAllMapped(RegExp(r'([^\n])(#[#]?\s*[🔍✅🎯💡][^\n]*)'), (m) => '${m.group(1)}\n\n${m.group(2)}');
  s = s.replaceAllMapped(RegExp(r'([^\n])(-\s*[✅🎯💡])'), (m) => '${m.group(1)}\n${m.group(2)}');
  s = s.replaceAllMapped(RegExp(r'([：:])\s*-\s*'), (m) => '${m.group(1)}\n- ');
  return s.trim();
}

class NovaFencePart {
  const NovaFencePart({
    this.lang = '',
    required this.body,
    this.isCode = false,
    this.open = false,
  });

  final String lang;
  final String body;
  final bool isCode;
  final bool open;
}

List<NovaFencePart> splitNovaMarkdownFences(String text) {
  final parts = <NovaFencePart>[];
  final re = RegExp(r'```(\w*)\n?([\s\S]*?)```');
  var last = 0;
  var hit = false;
  for (final m in re.allMatches(text)) {
    hit = true;
    if (m.start > last) parts.add(NovaFencePart(body: text.substring(last, m.start)));
    parts.add(NovaFencePart(
      lang: m.group(1)?.trim() ?? '',
      body: (m.group(2) ?? '').replaceAll(RegExp(r'\n$'), ''),
      isCode: true,
    ));
    last = m.end;
  }
  if (hit) {
    if (last < text.length) parts.add(NovaFencePart(body: text.substring(last)));
    return parts;
  }
  final open = RegExp(r'```(\w*)\n?([\s\S]*)$').firstMatch(text);
  if (open != null && text.indexOf('```') == text.lastIndexOf('```')) {
    final before = text.substring(0, open.start);
    if (before.isNotEmpty) parts.add(NovaFencePart(body: before));
    parts.add(NovaFencePart(
      lang: open.group(1)?.trim() ?? '',
      body: open.group(2) ?? '',
      isCode: true,
      open: true,
    ));
    return parts;
  }
  parts.add(NovaFencePart(body: text));
  return parts;
}
