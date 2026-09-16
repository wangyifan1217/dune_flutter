import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'nova_deliverable.dart';
import 'nova_file_utils.dart';
import 'nova_markdown.dart';
import 'nova_media.dart';

final Map<String, String> _novaDocumentTextCache = <String, String>{};

String _novaDocumentCacheKey({
  required String url,
  required String objectKey,
  required String fileName,
}) {
  return '${url.trim()}\u0001${objectKey.trim()}\u0001${fileName.trim()}';
}

Future<String> _fetchHttpText(
  String url, {
  Map<String, String> headers = const {},
}) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    if (headers.isNotEmpty) req.headers.addAll(headers);
    final resp = await client.send(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('读取失败（HTTP ${resp.statusCode}）');
    }
    final bytes = await resp.stream.toBytes();
    if (bytes.isEmpty) throw Exception('文件内容为空');
    if (isNovaFilesApiErrorBody(
      bytes,
      contentType: resp.headers['content-type'] ?? '',
    )) {
      throw Exception('文件不可访问');
    }
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    client.close();
  }
}

Future<String> loadNovaAttachmentMarkdown({
  required NovaMediaResolver resolver,
  String url = '',
  String objectKey = '',
  String bucket = 'im-attachments',
  String fileName = '',
  List<String> agentPathCandidates = const <String>[],
  List<int>? previewBytes,
}) async {
  if (previewBytes != null && previewBytes.isNotEmpty) {
    return utf8.decode(previewBytes, allowMalformed: true);
  }

  final rawUrl = url.trim();
  final rawKey = objectKey.trim();
  Object? lastError;

  Future<String> tryDirect(String absolute) async {
    final needsAuth = novaImageUrlNeedsAuthFetch(absolute) ||
        RegExp(r'/v1/files/download', caseSensitive: false).hasMatch(absolute);
    final headers = needsAuth ? resolver.novaDownloadHeaders() : const <String, String>{};
    if (isDirectHttpUrl(absolute) &&
        (needsAuth || isUrlLikelyDeviceReachable(absolute))) {
      return _fetchHttpText(absolute, headers: headers);
    }
    if (needsAuth) {
      return _fetchHttpText(absolute, headers: headers);
    }
    throw Exception('地址不可达');
  }

  try {
    final resolved = await resolver.resolveAttachmentAccessUrl(
      url: rawUrl,
      objectKey: rawKey,
      bucket: bucket,
    );
    return await tryDirect(resolved.trim());
  } catch (e) {
    lastError = e;
  }

  for (final key in [rawKey, rawUrl]) {
    if (key.isEmpty || isDirectHttpUrl(key)) continue;
    try {
      return await resolver.fetchTextViaStorageProxy(key, bucket: bucket);
    } catch (e) {
      lastError = e;
    }
  }

  if (isDirectHttpUrl(rawUrl)) {
    try {
      return await tryDirect(rawUrl);
    } catch (e) {
      lastError = e;
    }
  }

  try {
    return await resolver.fetchAgentFileText(
      fileName: fileName,
      agentPath: rawKey,
      agentPathCandidates: agentPathCandidates,
    );
  } catch (e) {
    lastError = e;
  }

  if (lastError != null) {
    throw lastError is Exception ? lastError as Exception : Exception('$lastError');
  }
  throw Exception('无法读取文档内容');
}

Future<void> openNovaMarkdownPreview(
  BuildContext context, {
  required NovaMediaResolver resolver,
  required String fileName,
  String url = '',
  String objectKey = '',
  String bucket = 'im-attachments',
  List<String> agentPathCandidates = const <String>[],
  Uint8List? previewBytes,
}) async {
  if (!novaIsPreviewableDocument(fileName)) {
    await openNovaFileDownload(
      context,
      resolver: resolver,
      url: url,
      objectKey: objectKey,
      fileName: fileName,
      bucket: bucket,
      previewBytes: previewBytes,
    );
    return;
  }
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭文档',
    barrierColor: const Color(0x66101830),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondary) {
      return Theme(
        data: Theme.of(context),
        child: NovaDocumentGlassOverlay(
          resolver: resolver,
          fileName: fileName,
          url: url,
          objectKey: objectKey,
          bucket: bucket,
          agentPathCandidates: agentPathCandidates,
          previewBytes: previewBytes,
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class NovaDocumentGlassOverlay extends StatefulWidget {
  const NovaDocumentGlassOverlay({
    super.key,
    required this.resolver,
    required this.fileName,
    this.url = '',
    this.objectKey = '',
    this.bucket = 'im-attachments',
    this.agentPathCandidates = const <String>[],
    this.previewBytes,
  });

  final NovaMediaResolver resolver;
  final String fileName;
  final String url;
  final String objectKey;
  final String bucket;
  final List<String> agentPathCandidates;
  final Uint8List? previewBytes;

  @override
  State<NovaDocumentGlassOverlay> createState() =>
      _NovaDocumentGlassOverlayState();
}

class _NovaDocumentGlassOverlayState extends State<NovaDocumentGlassOverlay> {
  String? _markdown;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await _loadNovaDocumentText(
        resolver: widget.resolver,
        url: widget.url,
        objectKey: widget.objectKey,
        bucket: widget.bucket,
        fileName: widget.fileName,
        agentPathCandidates: widget.agentPathCandidates,
        previewBytes: widget.previewBytes,
      );
      if (!mounted) return;
      setState(() {
        _markdown = text.trim().isNotEmpty ? text : '（空文档）';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e, fallback: '无法加载文档');
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    await openNovaFileDownload(
      context,
      resolver: widget.resolver,
      url: widget.url,
      objectKey: widget.objectKey,
      fileName: widget.fileName,
      bucket: widget.bucket,
      agentPathCandidates: widget.agentPathCandidates,
      previewBytes: widget.previewBytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: SizedBox(
                width: size.width < 720 ? size.width - 28 : 640,
                height: size.height * 0.86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Material(
                      color: const Color(0xD8FFFFFF),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '生成文件',
                                        style: DunesTypography.sans(
                                          fontSize: 11,
                                          color: DunesColors.text3,
                                        ),
                                      ),
                                      Text(
                                        widget.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: DunesTypography.sans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: DunesColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _loading ? null : _download,
                                  tooltip: '下载',
                                  icon: const Icon(Icons.download_outlined),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0x22FFFFFF)),
                          Expanded(child: _buildBody()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      children: [
        NovaMarkdownBody(
          text: _markdown ?? '',
          mediaResolver: widget.resolver,
        ),
      ],
    );
  }
}

/// 会话气泡内的半透明正文预览。
class NovaInlineDocumentGlass extends StatefulWidget {
  const NovaInlineDocumentGlass({
    super.key,
    required this.resolver,
    required this.file,
  });

  final NovaMediaResolver resolver;
  final NovaDeliverableItem file;

  @override
  State<NovaInlineDocumentGlass> createState() =>
      _NovaInlineDocumentGlassState();
}

class _NovaInlineDocumentGlassState extends State<NovaInlineDocumentGlass> {
  String? _text;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NovaInlineDocumentGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.url != widget.file.url ||
        oldWidget.file.effectiveAgentPath != widget.file.effectiveAgentPath) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await _loadNovaDocumentText(
        resolver: widget.resolver,
        url: widget.file.url,
        objectKey: widget.file.effectiveAgentPath,
        fileName: widget.file.name,
        agentPathCandidates: widget.file.agentPathCandidates,
      );
      if (!mounted) return;
      setState(() {
        _text = text.trim();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e, fallback: '无法预览正文');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 220),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0x73FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x55FFFFFF)),
          ),
          child: _buildInner(),
        ),
      ),
    );
  }

  Widget _buildInner() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Text(
        _error!,
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
      );
    }
    final raw = _text ?? '';
    if (raw.isEmpty) {
      return Text(
        '空文档',
        style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
      );
    }
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: NovaMarkdownBody(
        text: raw,
        mediaResolver: widget.resolver,
      ),
    );
  }
}

Future<String> _loadNovaDocumentText({
  required NovaMediaResolver resolver,
  String url = '',
  String objectKey = '',
  String bucket = 'im-attachments',
  String fileName = '',
  List<String> agentPathCandidates = const <String>[],
  Uint8List? previewBytes,
}) async {
  final key = _novaDocumentCacheKey(
    url: url,
    objectKey: objectKey,
    fileName: fileName,
  );
  final cached = _novaDocumentTextCache[key];
  if (cached != null) return cached;
  final text = await loadNovaAttachmentMarkdown(
    resolver: resolver,
    url: url,
    objectKey: objectKey,
    bucket: bucket,
    fileName: fileName,
    agentPathCandidates: agentPathCandidates,
    previewBytes: previewBytes,
  );
  final normalized = text.trim().isNotEmpty ? text : '（空文档）';
  _novaDocumentTextCache[key] = normalized;
  return normalized;
}
