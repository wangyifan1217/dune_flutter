import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import 'file_download.dart' as file_dl;

Future<void> showChatPdfPreview({
  required BuildContext context,
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChatPdfPreviewPage(
        service: service,
        payload: payload,
        fileName: fileName,
      ),
    ),
  );
}

bool chatPayloadIsPdf(Map<String, dynamic>? payload, String fileName) {
  final mime = (payload?['mimeType'] ?? '').toString().trim().toLowerCase();
  if (mime == 'application/pdf') return true;
  return fileName.trim().toLowerCase().endsWith('.pdf');
}

class ChatPdfPreviewPage extends StatefulWidget {
  const ChatPdfPreviewPage({
    super.key,
    required this.service,
    required this.payload,
    required this.fileName,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;

  @override
  State<ChatPdfPreviewPage> createState() => _ChatPdfPreviewPageState();
}

class _ChatPdfPreviewPageState extends State<ChatPdfPreviewPage> {
  PdfControllerPinch? _controller;
  bool _loading = true;
  bool _downloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<Uint8List> _loadPdfBytes() async {
    if (ConversationService.hasAuthMedia(widget.payload)) {
      return widget.service.loadChatMediaBytes(widget.payload);
    }
    final url = ConversationService.mediaDirectUrl(widget.payload);
    if (url.isEmpty) throw Exception('PDF 地址不可用');
    final client = http.Client();
    try {
      final resp = await client.get(Uri.parse(url));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('PDF 下载失败（HTTP ${resp.statusCode}）');
      }
      return resp.bodyBytes;
    } finally {
      client.close();
    }
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await _loadPdfBytes();
      if (!mounted) return;
      _controller?.dispose();
      _controller = PdfControllerPinch(
        document: PdfDocument.openData(bytes),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: 'PDF 加载失败');
      });
    }
  }

  Future<void> _downloadPdf() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await _loadPdfBytes();
      await file_dl.saveBytesAsFile(bytes, widget.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${widget.fileName}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e, fallback: '下载失败')),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _downloadPdf,
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 48, color: DunesColors.text3),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(fontSize: 14, color: DunesColors.text2),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadPdf,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return PdfViewPinch(
      controller: controller,
      padding: 10,
      scrollDirection: Axis.vertical,
    );
  }
}
