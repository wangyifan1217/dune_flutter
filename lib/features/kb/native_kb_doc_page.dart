import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../nova/nova_markdown.dart';
import 'native_kb_models.dart';
import 'native_kb_service.dart';

class NativeKbDocPage extends StatefulWidget {
  const NativeKbDocPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.docId,
    this.initialDoc,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final String docId;
  final NativeKbDocument? initialDoc;

  @override
  State<NativeKbDocPage> createState() => _NativeKbDocPageState();
}

class _NativeKbDocPageState extends State<NativeKbDocPage> {
  late final NativeKbService _service;
  NativeKbDocument? _doc;
  String? _markdown;
  String _fileName = '';
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
      final preview = await _service.loadDocumentPreview(
        docId: widget.docId,
        initialDoc: widget.initialDoc,
      );
      if (!mounted) return;
      setState(() {
        _doc = preview.doc;
        _markdown = preview.markdown;
        _fileName = preview.fileName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
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
            onPressed: () => widget.navigation.popTo('K1'),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '知识库 · 文档预览',
                  style: TextStyle(
                    fontFamily: 'Noto Sans SC',
                    fontSize: 9.5,
                    color: DunesColors.text3,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  doc?.title ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Noto Sans SC',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
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
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final doc = _doc!;
    if (_markdown != null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          NovaMarkdownBody(
            text: _markdown!.trim().isEmpty ? '（空文档）' : _markdown!,
            documentPreview: true,
          ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: DunesColors.text3.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              doc.title.isNotEmpty ? doc.title : _fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '暂无法预览此文档',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}
