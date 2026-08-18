import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import '../meeting/meeting_minutes_markdown.dart';
import 'file_download.dart' as file_dl;

bool chatPayloadIsMarkdown(Map<String, dynamic>? payload, String fileName) {
  final name = fileName.trim().toLowerCase();
  if (name.endsWith('.md') || name.endsWith('.markdown')) return true;
  final mime = (payload?['mimeType'] ?? '').toString().trim().toLowerCase();
  return mime == 'text/markdown' ||
      mime == 'text/x-markdown' ||
      mime.contains('markdown');
}

Future<void> showChatMarkdownPreview({
  required BuildContext context,
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
  String? initialLocalPath,
}) {
  final page = ChatMarkdownPreviewPage(
    service: service,
    payload: payload,
    fileName: fileName,
    initialLocalPath: initialLocalPath,
  );
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 28,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 920,
              maxHeight: size.height * 0.88,
              minWidth: 560,
              minHeight: 480,
            ),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: page,
            ),
          ),
        );
      },
    );
  }
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}

class ChatMarkdownPreviewPage extends StatefulWidget {
  const ChatMarkdownPreviewPage({
    super.key,
    required this.service,
    required this.payload,
    required this.fileName,
    this.initialLocalPath,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  final String? initialLocalPath;

  @override
  State<ChatMarkdownPreviewPage> createState() =>
      _ChatMarkdownPreviewPageState();
}

class _ChatMarkdownPreviewPageState extends State<ChatMarkdownPreviewPage> {
  Uint8List? _bytes;
  String _markdown = '';
  String? _error;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<Uint8List> _loadBytes() async {
    final cached = _bytes;
    if (cached != null && cached.isNotEmpty) return cached;
    final localPath = widget.initialLocalPath?.trim() ?? '';
    if (localPath.isNotEmpty) {
      return XFile(localPath).readAsBytes();
    }
    if (ConversationService.hasAuthMedia(widget.payload)) {
      return widget.service.loadChatMediaBytes(widget.payload);
    }
    final url = ConversationService.mediaDirectUrl(widget.payload);
    if (url.isEmpty) throw Exception('Markdown 地址不可用');
    final client = http.Client();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Markdown 下载失败（HTTP ${response.statusCode}）');
      }
      return response.bodyBytes;
    } finally {
      client.close();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = Uint8List.fromList(await _loadBytes());
      if (bytes.isEmpty) throw Exception('文件内容为空');
      var markdown = utf8.decode(bytes, allowMalformed: true);
      if (markdown.startsWith('\uFEFF')) markdown = markdown.substring(1);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _markdown = markdown;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: 'Markdown 加载失败');
      });
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _loadBytes();
      await file_dl.saveBytesAsFile(bytes, widget.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已保存 ${widget.fileName}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorText(e, fallback: '下载失败'))),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            onPressed: _loading || _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: '下载',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 48,
                color: DunesColors.text3,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 14,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: MeetingMinutesMarkdown(markdown: _markdown),
    );
  }
}
