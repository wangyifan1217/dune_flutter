import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'nova_deliverable.dart';
import 'nova_file_utils.dart';
import 'nova_markdown.dart';
import 'nova_media.dart';

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
  if (!novaIsMarkdownFile(fileName)) {
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
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _NovaMarkdownPreviewPage(
        resolver: resolver,
        fileName: fileName,
        url: url,
        objectKey: objectKey,
        bucket: bucket,
        agentPathCandidates: agentPathCandidates,
        previewBytes: previewBytes,
      ),
    ),
  );
}

class _NovaMarkdownPreviewPage extends StatefulWidget {
  const _NovaMarkdownPreviewPage({
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
  State<_NovaMarkdownPreviewPage> createState() => _NovaMarkdownPreviewPageState();
}

class _NovaMarkdownPreviewPageState extends State<_NovaMarkdownPreviewPage> {
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
      final text = await loadNovaAttachmentMarkdown(
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
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '文档预览',
                          style: const TextStyle(
                            fontFamily: 'Noto Sans SC',
                            fontSize: 10,
                            color: DunesColors.text3,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          widget.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Noto Sans SC',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.text,
                            decoration: TextDecoration.none,
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Center(
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
                        )
                      : ListView(
                          padding: const EdgeInsets.all(14),
                          children: [
                            NovaMarkdownBody(
                              text: _markdown ?? '',
                              mediaResolver: widget.resolver,
                              documentPreview: true,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
