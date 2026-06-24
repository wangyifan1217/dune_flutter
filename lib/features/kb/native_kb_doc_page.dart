import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'native_kb_models.dart';
import 'native_kb_service.dart';

class NativeKbDocPage extends StatefulWidget {
  const NativeKbDocPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.docId,
    required this.onAskAi,
    required this.onFallback,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String docId;
  final void Function(String docId) onAskAi;
  final VoidCallback onFallback;

  @override
  State<NativeKbDocPage> createState() => _NativeKbDocPageState();
}

class _NativeKbDocPageState extends State<NativeKbDocPage> {
  late final NativeKbService _service;
  NativeKbDocument? _doc;
  String? _markdown;
  String? _downloadUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = NativeKbService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    if (widget.docId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '文档 ID 无效';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await _service.fetchDocumentDetail(widget.docId);
      String? md;
      String? url;
      if (doc.fileObjectKey.isNotEmpty) {
        url = await _service.resolveDownloadUrl(doc.fileObjectKey);
        final ext = doc.fileExtension.toLowerCase();
        final isMd = ext == 'md' || doc.fileName.toLowerCase().endsWith('.md');
        if (isMd) {
          md = await _service.fetchMarkdownContent(doc.fileObjectKey);
        }
      }
      await _service.recordDocumentView(widget.docId);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _markdown = md;
        _downloadUrl = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openExternal() async {
    final url = _downloadUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? _buildError()
                      : _buildBody(),
            ),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final doc = _doc;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => widget.navigation.go('K1'),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('知识库 · 文档预览', style: TextStyle(fontSize: 9.5, color: DunesColors.text3)),
                Text(
                  doc?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (_downloadUrl != null)
            IconButton(onPressed: _openExternal, icon: const Icon(Icons.download_outlined, size: 20)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: _load, child: const Text('重试')),
                FilledButton(onPressed: widget.onFallback, child: const Text('切回 WebView')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final doc = _doc!;
    final ext = doc.fileExtension.toUpperCase();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip((ext.isEmpty ? '文档' : ext)),
            _chip(doc.statusLabel),
            if (doc.fileName.isNotEmpty) _chip(doc.fileName),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: DunesColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: const Color(0xFFF7F6F2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${ext.isEmpty ? '文档' : ext}${doc.fileName.isNotEmpty ? ' · ${doc.fileName}' : ''}',
                      style: const TextStyle(fontSize: 9, color: DunesColors.text3),
                    ),
                    Text(
                      doc.indexed ? 'INDEXED · RAGFlow' : doc.statusLabel,
                      style: const TextStyle(fontSize: 9, color: DunesColors.text3),
                    ),
                  ],
                ),
              ),
              if (_markdown != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _markdown!,
                    style: const TextStyle(fontSize: 11, height: 1.55, color: DunesColors.text),
                  ),
                )
              else if (_downloadUrl != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F6F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: DunesColors.borderSoft),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: DunesColors.accentSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.description_outlined, color: DunesColors.accentDeep),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(doc.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  const Text('点击下方按钮在浏览器中打开原文', style: TextStyle(fontSize: 9.5, color: DunesColors.text3)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _openExternal,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2F5D62),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: const Text('打开文档'),
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无法预览此文档', style: TextStyle(fontSize: 11, color: DunesColors.text3)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          children: [
            Icon(Icons.visibility_outlined, size: 14, color: DunesColors.text3),
            SizedBox(width: 6),
            Text('已记录最近查阅', style: TextStyle(fontSize: 10, color: DunesColors.text3)),
          ],
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: DunesColors.text2)),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => widget.navigation.go('K1'),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('返回知识库'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: widget.docId.isEmpty ? null : () => widget.onAskAi(widget.docId),
              style: FilledButton.styleFrom(backgroundColor: DunesColors.accentDeep),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('用 AI 问这篇'),
            ),
          ),
        ],
      ),
    );
  }
}
