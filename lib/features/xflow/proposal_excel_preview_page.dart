import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';

/// 打开 Excel 原文预览。
///
/// - 手机：App 内 WebView 渲染 HTML 预览。
/// - 桌面（Win / macOS）：不用 WebView（macOS + Impeller 下 Platform View
///   会导致整窗发灰/花屏），改为系统浏览器打开，失败则下载并用本地应用打开 .xlsx。
Future<void> openProposalExcelPreview({
  required BuildContext context,
  required AuthSession session,
  required String archiveId,
  String fileName = '提案.xlsx',
}) async {
  final id = archiveId.trim();
  if (id.isEmpty) {
    showDunesToast(context, '归档 ID 无效', kind: DunesToastKind.error);
    return;
  }
  final name = fileName.trim().isEmpty ? '提案.xlsx' : fileName.trim();
  if (isDesktopCommOnly) {
    await _openDesktopExcelPreview(
      context: context,
      session: session,
      archiveId: id,
      fileName: name,
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProposalExcelPreviewPage(
        session: session,
        archiveId: id,
        fileName: name,
      ),
    ),
  );
}

String _proposalApiBase(AuthSession session) =>
    session.apiBase.trim().replaceAll(RegExp(r'/$'), '');

Uri _previewUri(AuthSession session, String archiveId) {
  final base = _proposalApiBase(session);
  final url = '$base/proposals/${Uri.encodeComponent(archiveId)}/preview.html';
  final token = session.token.trim();
  if (token.isEmpty) return Uri.parse(url);
  return Uri.parse('$url?token=${Uri.encodeComponent(token)}');
}

String _rawUrl(AuthSession session, String archiveId) =>
    '${_proposalApiBase(session)}/proposals/${Uri.encodeComponent(archiveId)}/raw';

Map<String, String> _authHeaders(AuthSession session) {
  final token = session.token.trim();
  if (token.isEmpty) return const {};
  return {'Authorization': 'Bearer $token'};
}

Future<void> _openDesktopExcelPreview({
  required BuildContext context,
  required AuthSession session,
  required String archiveId,
  required String fileName,
}) async {
  final uri = _previewUri(session, archiveId);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) {
      if (context.mounted) {
        showDunesToast(context, '已在浏览器中打开 Excel 预览');
      }
      return;
    }
  } catch (_) {
    // 浏览器打不开时走本地下载打开。
  }

  if (!context.mounted) return;
  showDunesToast(context, '正在下载并用本地应用打开…');
  try {
    final path = await _downloadProposalExcel(
      session: session,
      archiveId: archiveId,
      fileName: fileName,
    );
    if (!context.mounted) return;
    if (path == null || path.isEmpty) {
      showDunesToast(context, '打开失败', kind: DunesToastKind.error);
      return;
    }
    await file_dl.openLocalFile(path);
    if (!context.mounted) return;
    showDunesToast(context, '已打开：$fileName');
  } catch (e) {
    if (!context.mounted) return;
    showDunesToast(context, '打开失败：$e', kind: DunesToastKind.error);
  }
}

Future<String?> _downloadProposalExcel({
  required AuthSession session,
  required String archiveId,
  required String fileName,
}) async {
  final resp = await http.get(
    Uri.parse(_rawUrl(session, archiveId)),
    headers: _authHeaders(session),
  );
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  var name = fileName;
  if (!name.toLowerCase().endsWith('.xlsx')) {
    name = '$name.xlsx';
  }
  return file_dl.saveBytesAsFile(Uint8List.fromList(resp.bodyBytes), name);
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

  String get _apiBase => _proposalApiBase(widget.session);

  String get _previewUrl =>
      '$_apiBase/proposals/${Uri.encodeComponent(widget.archiveId)}/preview.html';

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
        headers: _authHeaders(widget.session),
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
      final path = await _downloadProposalExcel(
        session: widget.session,
        archiveId: widget.archiveId,
        fileName: widget.fileName,
      );
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        showDunesToast(context, '下载失败', kind: DunesToastKind.error);
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
