import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_service.dart';
import '../kb/kb_document_coordinator.dart';
import '../kb/native_kb_service.dart';
import 'file_download.dart' as file_dl;

Future<void> showChatPdfPreview({
  required BuildContext context,
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
  AuthSession? saveToKbSession,
  Uint8List? initialBytes,
}) {
  final page = ChatPdfPreviewPage(
    service: service,
    payload: payload,
    fileName: fileName,
    saveToKbSession: saveToKbSession,
    initialBytes: initialBytes,
  );
  // PDF 渲染层不能包 SelectionArea，否则 Windows 上常出现整页灰屏。
  if (isDesktopCommOnly) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
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
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => page),
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
    this.saveToKbSession,
    this.initialBytes,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  /// 非空时提供「存入我的知识库」（用于 IM 转发的知识库文档）。
  final AuthSession? saveToKbSession;
  /// 知识库等场景可直接传入已下载字节，跳过会话附件拉取。
  final Uint8List? initialBytes;

  @override
  State<ChatPdfPreviewPage> createState() => _ChatPdfPreviewPageState();
}

class _ChatPdfPreviewPageState extends State<ChatPdfPreviewPage> {
  PdfControllerPinch? _controller;
  bool _loading = true;
  bool _downloading = false;
  bool _savingToKb = false;
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
    final initial = widget.initialBytes;
    if (initial != null && initial.isNotEmpty) return initial;
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
      final raw = await _loadPdfBytes();
      if (!mounted) return;
      // 拷贝一份，避免外部 buffer 被回收后 pdfx 渲染灰屏。
      final bytes = Uint8List.fromList(raw);
      if (bytes.length < 5 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw Exception('文件不是有效的 PDF');
      }
      final document = await PdfDocument.openData(bytes);
      if (!mounted) {
        await document.close();
        return;
      }
      _controller?.dispose();
      _controller = PdfControllerPinch(
        document: Future<PdfDocument>.value(document),
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
    if (_downloading || _savingToKb) return;
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

  Future<void> _saveToKb() async {
    final session = widget.saveToKbSession;
    if (session == null || _savingToKb || _downloading) return;
    final title = widget.fileName.trim().isNotEmpty
        ? widget.fileName.trim()
        : '文档';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存入我的知识库'),
        content: Text(
          '将把「$title」存入你的知识库，上传后可检索引用。\n\n是否继续？',
          style: DunesTypography.sans(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认存入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingToKb = true);
    try {
      final bytes = await _loadPdfBytes();
      if (bytes.isEmpty) throw Exception('文件内容为空');
      final kb = NativeKbService(session: session);
      await kb.uploadDocument(
        bytes: bytes,
        fileName: widget.fileName,
        title: title,
      );
      KbDocumentCoordinator.instance.notifyChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存入你的知识库，正在后台解析入库')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorText(e, fallback: '存入知识库失败，请稍后重试')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingToKb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSaveToKb = widget.saveToKbSession != null;
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
          if (canSaveToKb)
            IconButton(
              onPressed: (_downloading || _savingToKb) ? null : _saveToKb,
              icon: _savingToKb
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              tooltip: '存入我的知识库',
            ),
          IconButton(
            onPressed: (_downloading || _savingToKb) ? null : _downloadPdf,
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
