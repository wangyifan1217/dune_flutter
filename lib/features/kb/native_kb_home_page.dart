import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'native_kb_models.dart';
import 'native_kb_service.dart';

class NativeKbHomePage extends StatefulWidget {
  const NativeKbHomePage({
    super.key,
    required this.session,
    required this.navigation,
    required this.onBack,
    required this.onOpenChat,
    required this.onFallback,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final VoidCallback onBack;
  final VoidCallback onOpenChat;
  final VoidCallback onFallback;

  @override
  State<NativeKbHomePage> createState() => _NativeKbHomePageState();
}

class _NativeKbHomePageState extends State<NativeKbHomePage> {
  late final NativeKbService _service;
  NativeKbSummary? _summary;
  bool _loading = true;
  bool _syncing = false;
  bool _uploading = false;
  String? _error;
  String _syncStatus = '打开页面自动读本地库 · 后台同步 RAGFlow · 可手动刷新';
  Timer? _parsePollTimer;

  @override
  void initState() {
    super.initState();
    _service = NativeKbService(session: widget.session);
    _load();
  }

  @override
  void dispose() {
    _parsePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final summary = await _service.fetchSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        if (!silent) _loading = false;
      });
      _syncParsePoll(summary.documents);
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _syncParsePoll(List<NativeKbDocument> docs) {
    _parsePollTimer?.cancel();
    _parsePollTimer = null;
    if (!nativeKbHasPendingParse(docs)) return;
    _parsePollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_load(silent: true));
    });
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncStatus = '正在同步 RAGFlow 文件夹与文件…';
    });
    try {
      await _service.fetchSummary();
      await _load();
      if (!mounted) return;
      setState(() => _syncStatus = '同步完成，已更新知识库状态');
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncStatus = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final summary = _summary;
    if (summary == null || !summary.ready) {
      _toast('Nova 知识库未就绪，请稍后重试', error: true);
      return;
    }
    const types = <XTypeGroup>[
      XTypeGroup(
        label: 'documents',
        extensions: <String>['pdf', 'doc', 'docx', 'xlsx', 'xls', 'md'],
      ),
    ];
    final file = await openFile(acceptedTypeGroups: types);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      await _service.uploadDocument(bytes: await file.readAsBytes(), fileName: file.name);
      await _load();
      if (!mounted) return;
      _toast('上传成功，正在解析入库');
    } catch (e) {
      if (!mounted) return;
      _toast('上传失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteDoc(NativeKbDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文档'),
        content: Text('确定删除「${doc.title}」？将从知识库中移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteDocument(doc.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast('删除失败：$e', error: true);
    }
  }

  Future<void> _enterChat() async {
    final summary = _summary;
    if (summary != null && !summary.ready && summary.documents.every((d) => !d.indexed)) {
      _toast('请先上传文档并等待解析完成');
      return;
    }
    widget.onOpenChat();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      msg,
      kind: error || dunesToastLooksLikeError(msg)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _buildHero(),
                        _buildSyncRow(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sectionLabel('上传', '知识库文档'),
                              const SizedBox(height: 8),
                              _buildUploadPanel(),
                              const SizedBox(height: 14),
                              _sectionLabel('分类', '知识库目录',
                                  count: '${_summary?.categoryCount ?? 0} 个'),
                              const SizedBox(height: 8),
                              _buildCategoryGrid(),
                              const SizedBox(height: 14),
                              _sectionLabel('我的', '文档', count: '${_summary?.documentCount ?? 0} 篇'),
                              const SizedBox(height: 8),
                              _buildDocList(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
            const Text('知识库加载失败', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
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

  Widget _buildHero() {
    final s = _summary;
    final phone = widget.session.phone;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B3A3F), Color(0xFF2F5D62), Color(0xFF5F8B8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
          const Text(
            'DUNES KNOWLEDGE · 企业知识库',
            style: TextStyle(color: Colors.white70, fontSize: 9, letterSpacing: 0.6, fontWeight: FontWeight.w600),
          ),
          const Text('知识库', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          const Text(
            '公司制度 / 流程 SOP / 合同模板 / 法务条款 / 财务规则 — 一处查全',
            style: TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.45),
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.13))),
            ),
            child: Row(
              children: [
                _heroStat('${s?.documentCount ?? 0}', '文档'),
                const SizedBox(width: 14),
                _heroStat('${s?.categoryCount ?? 0}', '分类'),
                const SizedBox(width: 14),
                _heroStat('${s?.unreadCount ?? 0}', '未读'),
              ],
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '我的知识库（$phone）',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        Text(label.toUpperCase(), style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 8, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildSyncRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 16),
            label: const Text('同步 RAGFlow', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_syncStatus, style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String accent, String title, {String? count}) {
    return Row(
      children: [
        Text(accent, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DunesColors.accentDeep)),
        Text(' · $title', style: const TextStyle(fontSize: 11, color: DunesColors.text2)),
        const Expanded(child: Divider(indent: 8, endIndent: 8, color: DunesColors.borderSoft)),
        if (count != null) Text(count, style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
      ],
    );
  }

  Widget _buildUploadPanel() {
    final ready = _summary?.ready ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: ready && !_uploading ? _pickAndUpload : null,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: DunesColors.borderSoft),
              ),
              child: Column(
                children: [
                  Icon(Icons.upload_file, color: ready ? DunesColors.accentDeep : DunesColors.text3, size: 28),
                  const SizedBox(height: 6),
                  const Text('点击选择 PDF / Word / Excel / Markdown', style: TextStyle(fontSize: 11.5)),
                  const SizedBox(height: 4),
                  Text(
                    ready ? '支持 PDF / Word / Excel / Markdown · 上传后自动解析' : 'Nova 知识库未就绪，请稍后重试',
                    style: const TextStyle(fontSize: 10, color: DunesColors.text3),
                  ),
                ],
              ),
            ),
          ),
          if (_uploading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            const Text('正在上传并解析…', style: TextStyle(fontSize: 10, color: DunesColors.text3)),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final phone = widget.session.phone;
    final count = _summary?.documentCount ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.border),
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
            child: const Icon(Icons.folder_outlined, color: DunesColors.accentDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的知识库${phone.isNotEmpty ? '（$phone）' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                Text('$count 篇', style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
              ],
            ),
          ),
          IconButton(
            onPressed: _enterChat,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            tooltip: '问知识库',
          ),
        ],
      ),
    );
  }

  Widget _buildDocList() {
    final docs = _summary?.documents ?? const <NativeKbDocument>[];
    if (docs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DunesColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: DunesColors.text3),
            SizedBox(width: 8),
            Expanded(child: Text('暂无文档，请先上传', style: TextStyle(fontSize: 11, color: DunesColors.text3))),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final doc in docs)
          Container(
            key: ValueKey(doc.id),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DunesColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EEE8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_outlined, size: 18, color: DunesColors.text2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EEE8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (doc.fileExtension.isEmpty ? 'DOC' : doc.fileExtension).toUpperCase(),
                              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(doc.statusLabel, style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
                        ],
                      ),
                    ],
                  ),
                ),
                Material(
                  color: DunesColors.coralSoft,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => _deleteDoc(doc),
                    borderRadius: BorderRadius.circular(8),
                    child: const SizedBox(
                      width: 30,
                      height: 30,
                      child: Icon(Icons.delete_outline, size: 16, color: DunesColors.coral),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
