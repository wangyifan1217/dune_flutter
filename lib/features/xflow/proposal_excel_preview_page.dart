import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';

/// App 内打开 Excel 原文 HTML 预览，并支持下载原始 .xlsx。
Future<void> openProposalExcelPreview({
  required BuildContext context,
  required AuthSession session,
  required String archiveId,
  String fileName = '提案.xlsx',
}) {
  final id = archiveId.trim();
  if (id.isEmpty) {
    showDunesToast(context, '归档 ID 无效', kind: DunesToastKind.error);
    return Future.value();
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProposalExcelPreviewPage(
        session: session,
        archiveId: id,
        fileName: fileName.trim().isEmpty ? '提案.xlsx' : fileName.trim(),
      ),
    ),
  );
}

class ProposalExcelPreviewPage extends StatefulWidget {
  const ProposalExcelPreviewPage({
    super.key,
    required this.session,
    required this.archiveId,
    required this.fileName,
  });

  final AuthSession session;
  final String archiveId;
  final String fileName;

  @override
  State<ProposalExcelPreviewPage> createState() =>
      _ProposalExcelPreviewPageState();
}

class _ProposalExcelPreviewPageState extends State<ProposalExcelPreviewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _downloading = false;
  String? _error;

  String get _apiBase {
    final base = widget.session.apiBase.trim().replaceAll(RegExp(r'/$'), '');
    return base;
  }

  String get _previewUrl =>
      '$_apiBase/proposals/${Uri.encodeComponent(widget.archiveId)}/preview.html';

  String get _rawUrl =>
      '$_apiBase/proposals/${Uri.encodeComponent(widget.archiveId)}/raw';

  Map<String, String> get _authHeaders {
    final token = widget.session.token.trim();
    if (token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = err.description.isNotEmpty ? err.description : '预览加载失败';
            });
          },
        ),
      );
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 带鉴权头加载 HTML，避免 WebView 直接 GET 丢 token。
      final resp = await http.get(
        Uri.parse(_previewUrl),
        headers: _authHeaders,
      );
      if (!mounted) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _loading = false;
          _error = '预览加载失败（HTTP ${resp.statusCode}）';
        });
        return;
      }
      final html = resp.body;
      await _controller.loadHtmlString(html, baseUrl: _apiBase);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '预览加载失败：$e';
      });
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final resp = await http.get(Uri.parse(_rawUrl), headers: _authHeaders);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      var name = widget.fileName;
      if (!name.toLowerCase().endsWith('.xlsx')) {
        name = '$name.xlsx';
      }
      final path = await file_dl.saveBytesAsFile(
        Uint8List.fromList(resp.bodyBytes),
        name,
      );
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        showDunesToast(context, '下载失败', kind: DunesToastKind.error);
      } else if (isDesktopCommOnly) {
        try {
          await file_dl.openLocalFile(path);
          if (!mounted) return;
          showDunesToast(context, '已打开：$name');
        } catch (_) {
          if (!mounted) return;
          showDunesToast(context, '已保存：$path');
        }
      } else {
        showDunesToast(context, '已保存：$path');
      }
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '下载失败：$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Excel 原文',
          style: DunesTypography.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DunesColors.text,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_downloading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '下载',
              onPressed: _download,
              icon: const Icon(Icons.download_rounded, size: 22),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: DunesColors.borderSoft),
        ),
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: DunesTypography.sans(
                        fontSize: 13,
                        color: DunesColors.text2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadPreview,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading && _error == null)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}
