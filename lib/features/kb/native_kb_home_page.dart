import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_preview_page.dart';
import '../chat/chat_pdf_preview.dart';
import '../chat/file_download.dart' as file_dl;
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../drive/chat_save_to_drive.dart';
import '../drive/native_drive_service.dart';
import '../shell/dunes_toast.dart';
import 'kb_chat_share.dart';
import 'kb_document_coordinator.dart';
import 'kb_upload_coordinator.dart';
import 'native_kb_models.dart';
import 'native_kb_service.dart';

const _driveBlue = Color(0xFF3B82F6);
const _driveBlueSoft = Color(0xFFEFF6FF);
const _kbAccent = Color(0xFF7B5CD8);

/// 知识库每次上传后都会解析入库，一次过多容易排队过久；5 个够一批相关文档。
const _maxKbUploadBatch = 5;

class NativeKbHomePage extends StatefulWidget {
  const NativeKbHomePage({
    super.key,
    required this.session,
    required this.navigation,
    required this.onBack,
    required this.onOpenChat,
    required this.onOpenDoc,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final VoidCallback onBack;
  final VoidCallback onOpenChat;
  final void Function(NativeKbDocument doc) onOpenDoc;

  @override
  State<NativeKbHomePage> createState() => _NativeKbHomePageState();
}

class _NativeKbHomePageState extends State<NativeKbHomePage> {
  late final NativeKbService _service;
  late final ConversationService _chatService;
  NativeKbSummary? _summary;
  final List<NativeKbDocument> _pageDocs = <NativeKbDocument>[];
  bool _loading = true;
  bool _syncing = false;
  bool _dragging = false;
  String? _forwardingDocId;
  String? _savingDriveDocId;
  final Set<String> _driveSavedDocKeys = <String>{};
  String? _error;
  String _syncStatus = '打开页面自动读本地库 · 后台同步 RAGFlow · 可手动刷新';
  Timer? _parsePollTimer;
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  int _listTotal = 0;
  static const int _pageSize = 20;
  final ScrollController _scroll = ScrollController();

  bool get _uploading => KbUploadCoordinator.instance.isUploading;
  String? get _uploadProgress {
    final text = KbUploadCoordinator.instance.progressText.trim();
    return text.isEmpty ? null : text;
  }

  @override
  void initState() {
    super.initState();
    _service = NativeKbService(session: widget.session);
    _chatService = ConversationService(session: widget.session);
    KbUploadCoordinator.instance.addListener(_onKbUploadChanged);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    KbUploadCoordinator.instance.removeListener(_onKbUploadChanged);
    _parsePollTimer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onKbUploadChanged() {
    if (!mounted) return;
    setState(() {});
    final toast = KbUploadCoordinator.instance.takeToast();
    if (toast != null) {
      _toast(toast.message, error: toast.error);
      unawaited(_load(silent: true));
    }
  }

  Future<void> _load({
    bool silent = false,
    bool reset = true,
    bool refreshSummary = true,
  }) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (reset && _pageDocs.isNotEmpty) {
      setState(() => _searching = _search.text.trim().isNotEmpty);
    }
    Object? summaryError;
    Object? listError;
    NativeKbSummary? summary = refreshSummary ? null : _summary;
    NativeKbDocumentPage? listPage;
    if (refreshSummary) {
      try {
        summary = await _service.fetchSummary();
      } catch (e) {
        summaryError = e;
      }
    }
    try {
      listPage = await _service.listDocuments(
        keyword: _search.text.trim(),
        page: 0,
        size: _pageSize,
      );
    } catch (e) {
      listError = e;
    }
    if (listPage == null && summary != null) {
      listPage = _pageFromNovaDocs(
        summary.documents,
        keyword: _search.text.trim(),
        page: 0,
      );
    }
    if (!mounted) return;
    if (summary == null && listPage == null) {
      if (!silent) {
        setState(() {
          _error = friendlyErrorText(
            summaryError ?? listError,
            fallback: '知识库加载失败',
          );
          _loading = false;
          _searching = false;
          _loadingMore = false;
        });
      }
      return;
    }
    final pageDocs = listPage?.items ?? const <NativeKbDocument>[];
    final listTotal = listPage?.total ?? pageDocs.length;
    setState(() {
      if (summary != null) _summary = summary;
      _pageDocs
        ..clear()
        ..addAll(pageDocs);
      _listTotal = listTotal;
      _page = 0;
      _hasMore = pageDocs.length >= _pageSize && pageDocs.length < listTotal;
      if (!silent) _loading = false;
      _searching = false;
      _loadingMore = false;
    });
    _syncParsePoll(pageDocs);
    unawaited(_refreshDriveSavedStatus(pageDocs, replace: true));
    if (!silent) {
      unawaited(_healLocalMirror());
    }
    _scheduleLoadMoreIfShort();
  }

  void _onScroll() {
    if (!_scroll.hasClients ||
        _loading ||
        _searching ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  void _scheduleLoadMoreIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore || _loadingMore || _loading) return;
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 80) {
        unawaited(_loadMore());
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _searching || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    NativeKbDocumentPage? listPage;
    try {
      listPage = await _service.listDocuments(
        keyword: _search.text.trim(),
        page: nextPage,
        size: _pageSize,
      );
    } catch (_) {
      final fallbackDocs = _summary?.documents ?? const <NativeKbDocument>[];
      if (fallbackDocs.isNotEmpty) {
        listPage = _pageFromNovaDocs(
          fallbackDocs,
          keyword: _search.text.trim(),
          page: nextPage,
        );
      }
    }
    if (!mounted) return;
    if (listPage == null) {
      setState(() => _loadingMore = false);
      return;
    }
    final existing = _pageDocs.map((d) => d.id).toSet();
    final appended = listPage.items
        .where((d) => !existing.contains(d.id))
        .toList(growable: false);
    final nextTotal = listPage.total;
    final fetchedCount = listPage.items.length;
    setState(() {
      _pageDocs.addAll(appended);
      _page = nextPage;
      _listTotal = nextTotal;
      _hasMore = fetchedCount >= _pageSize && _pageDocs.length < _listTotal;
      _loadingMore = false;
    });
    _syncParsePoll(_pageDocs);
    unawaited(_refreshDriveSavedStatus(appended, replace: false));
    _scheduleLoadMoreIfShort();
  }

  NativeKbDocumentPage _pageFromNovaDocs(
    List<NativeKbDocument> docs, {
    required String keyword,
    required int page,
  }) {
    final q = keyword.trim().toLowerCase();
    final filtered = q.isEmpty
        ? docs
        : docs
              .where((doc) {
                return doc.title.toLowerCase().contains(q) ||
                    doc.fileName.toLowerCase().contains(q) ||
                    doc.fileExtension.toLowerCase().contains(q);
              })
              .toList(growable: false);
    final start = page <= 0 ? 0 : page * _pageSize;
    if (start >= filtered.length) {
      return NativeKbDocumentPage(
        items: const <NativeKbDocument>[],
        page: page,
        size: _pageSize,
        total: filtered.length,
      );
    }
    final end = start + _pageSize > filtered.length
        ? filtered.length
        : start + _pageSize;
    return NativeKbDocumentPage(
      items: filtered.sublist(start, end),
      page: page,
      size: _pageSize,
      total: filtered.length,
    );
  }

  Future<void> _healLocalMirror() async {
    try {
      await _service.syncRagflow();
      if (mounted) await _load(silent: true);
    } catch (_) {}
  }

  String _driveSourceKeyForDoc(NativeKbDocument doc) {
    final share = KbChatDocShare.fromDocument(doc);
    final id = share.openDocId.trim().isNotEmpty
        ? share.openDocId.trim()
        : doc.id.trim();
    return id.isEmpty ? '' : 'kb-doc-$id';
  }

  Future<void> _refreshDriveSavedStatus(
    List<NativeKbDocument> docs, {
    bool replace = true,
  }) async {
    final keys = docs
        .map(_driveSourceKeyForDoc)
        .where((k) => k.isNotEmpty)
        .toList(growable: false);
    if (keys.isEmpty) return;
    final drive = NativeDriveService(session: widget.session);
    try {
      final saved = await drive.fetchChatSavedKeys(keys);
      if (!mounted) return;
      setState(() {
        if (replace) _driveSavedDocKeys.clear();
        _driveSavedDocKeys.addAll(saved);
      });
    } catch (_) {
      // 标记查询失败不影响列表。
    } finally {
      drive.close();
    }
  }

  void _syncParsePoll(List<NativeKbDocument> docs) {
    _parsePollTimer?.cancel();
    _parsePollTimer = null;
    if (!nativeKbHasPendingParse(docs)) return;
    _parsePollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_refreshVisibleDocStatus());
    });
  }

  Future<void> _refreshVisibleDocStatus() async {
    if (_pageDocs.isEmpty) return;
    try {
      final size = _pageDocs.length > 100 ? 100 : _pageDocs.length;
      final page = await _service.listDocuments(
        keyword: _search.text.trim(),
        page: 0,
        size: size < 1 ? _pageSize : size,
      );
      if (!mounted) return;
      final byId = <String, NativeKbDocument>{
        for (final doc in page.items) doc.id: doc,
      };
      setState(() {
        for (var i = 0; i < _pageDocs.length; i++) {
          final fresh = byId[_pageDocs[i].id];
          if (fresh == null) continue;
          _pageDocs[i] = _pageDocs[i].copyWith(
            ingestionStatus: fresh.ingestionStatus,
            indexed: fresh.indexed,
            runStatus: fresh.runStatus,
            fileObjectKey: fresh.fileObjectKey.isNotEmpty
                ? fresh.fileObjectKey
                : _pageDocs[i].fileObjectKey,
            localDocId: fresh.localDocId.isNotEmpty
                ? fresh.localDocId
                : _pageDocs[i].localDocId,
          );
        }
        _listTotal = page.total;
      });
      _syncParsePoll(_pageDocs);
    } catch (_) {}
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncStatus = '正在同步 RAGFlow 文件夹与文件…';
    });
    try {
      try {
        await _service.syncRagflow();
      } catch (e) {
        if (!mounted) return;
        setState(
          () => _syncStatus = friendlyErrorText(
            e,
            fallback: 'RAGFlow 同步未完成，已刷新本地列表',
          ),
        );
      }
      await _load(silent: true);
      if (!mounted) return;
      if (!_syncStatus.contains('未完成') && !_syncStatus.contains('失败')) {
        setState(() => _syncStatus = '同步完成，已更新知识库状态');
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _syncStatus = friendlyErrorText(e, fallback: '同步失败，请稍后重试'),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  bool get _supportsDesktopDrop => isDesktopCommOnly;

  Future<void> _pickAndUpload() async {
    final summary = _summary;
    if (summary == null || !summary.ready) {
      _toast('Nova 知识库未就绪，请稍后重试', error: true);
      return;
    }
    if (_uploading) return;
    final types = <XTypeGroup>[
      XTypeGroup(
        label: 'kb-upload',
        extensions: kChatKbUploadExtensions.toList(growable: false),
      ),
    ];
    final List<XFile> files;
    if (_supportsDesktopDrop) {
      files = await _openDocumentFilesWithFallback(types);
    } else {
      final file = await _openDocumentFileWithFallback(types);
      files = file == null ? const <XFile>[] : <XFile>[file];
    }
    if (files.isEmpty) return;
    await _ingestKbFiles(files);
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (_uploading) return;
    final summary = _summary;
    if (summary == null || !summary.ready) {
      _toast('Nova 知识库未就绪，请稍后重试', error: true);
      return;
    }
    if (mounted) setState(() => _dragging = false);
    final files = <XFile>[];
    for (final item in detail.files) {
      if (item is DropItemDirectory) continue;
      if (item.path.isEmpty) continue;
      files.add(XFile(item.path, name: item.name));
    }
    if (files.isEmpty) {
      _toast('请拖入文件（不支持文件夹）', error: true);
      return;
    }
    await _ingestKbFiles(files);
  }

  Future<void> _ingestKbFiles(List<XFile> picked) async {
    if (_uploading || picked.isEmpty) return;
    final accepted = <XFile>[];
    var skippedType = 0;
    for (final file in picked) {
      if (chatFileSupportsKbUpload(file.name)) {
        accepted.add(file);
      } else {
        skippedType++;
      }
    }
    if (accepted.isEmpty) {
      _toast('仅支持 $kChatKbUploadSupportLabel', error: true);
      return;
    }
    if (skippedType > 0) {
      _toast('已忽略 $skippedType 个不支持的文件类型');
    }
    var files = accepted;
    if (files.length > _maxKbUploadBatch) {
      files = files.take(_maxKbUploadBatch).toList(growable: false);
      _toast('一次最多 $_maxKbUploadBatch 个，已取前 $_maxKbUploadBatch 个');
    }
    if (!mounted) return;
    final confirmed = await _confirmKbUpload(files);
    if (confirmed != true || !mounted) return;

    unawaited(
      KbUploadCoordinator.instance.enqueue(
        session: widget.session,
        files: files,
      ),
    );
  }

  Future<bool?> _confirmKbUpload(List<XFile> files) {
    final names = files.map((f) => f.name).toList(growable: false);
    final content = files.length == 1
        ? '将把「${names.first}」上传到你的知识库，上传后可检索引用。\n\n是否继续？'
        : '将把以下 ${files.length} 个文件上传到你的知识库，上传后可检索引用。\n\n'
              '${names.map((n) => '· $n').join('\n')}\n\n是否继续？';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传到知识库'),
        content: Text(
          content,
          style: DunesTypography.sans(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认上传'),
          ),
        ],
      ),
    );
  }

  Future<List<XFile>> _openDocumentFilesWithFallback(
    List<XTypeGroup> types,
  ) async {
    try {
      return await openFiles(acceptedTypeGroups: types);
    } catch (_) {
      try {
        return await openFiles();
      } catch (_) {
        final file = await _openDocumentFileWithFallback(types);
        return file == null ? const <XFile>[] : <XFile>[file];
      }
    }
  }

  Future<XFile?> _openDocumentFileWithFallback(List<XTypeGroup> types) async {
    try {
      return await openFile(acceptedTypeGroups: types);
    } catch (_) {
      // iOS 某些系统版本在带类型过滤时不会弹起选择器，降级后再尝试一次。
      return openFile();
    }
  }

  Future<void> _deleteDoc(NativeKbDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文档'),
        content: Text('确定删除「${doc.title}」？将从知识库中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final previousSummary = _summary;
    final previousPage = List<NativeKbDocument>.from(_pageDocs);
    final previousTotal = _listTotal;
    setState(() {
      _pageDocs.removeWhere((d) => d.id == doc.id);
      if (_listTotal > 0) _listTotal -= 1;
      if (previousSummary != null) {
        final nextDocs = previousSummary.documents
            .where((d) => d.id != doc.id)
            .toList(growable: false);
        _summary = NativeKbSummary(
          documentCount: nextDocs.length,
          categoryCount: previousSummary.categoryCount,
          unreadCount: previousSummary.unreadCount,
          ready: previousSummary.ready,
          documents: nextDocs,
          folderId: previousSummary.folderId,
          message: previousSummary.message,
        );
      }
    });
    _syncParsePoll(_pageDocs);
    try {
      await _service.deleteDocument(
        doc.novaDocumentId,
        folderId: _summary?.folderId,
      );
      KbDocumentCoordinator.instance.notifyChanged();
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (previousSummary != null) _summary = previousSummary;
        _pageDocs
          ..clear()
          ..addAll(previousPage);
        _listTotal = previousTotal;
      });
      _syncParsePoll(previousPage);
      _toast('删除失败：${friendlyErrorText(e)}', error: true);
    }
  }

  bool _isMarkdownDoc(NativeKbDocument doc, String fileName) {
    final ext = doc.fileExtension.trim().toLowerCase();
    if (ext == 'md' || ext == 'markdown') return true;
    final name = fileName.trim().toLowerCase();
    return name.endsWith('.md') || name.endsWith('.markdown');
  }

  static const int _inAppPdfMaxBytes = 8 * 1024 * 1024;

  Future<T?> _withOpenProgress<T>(Future<T> Function() action) async {
    if (!mounted) return null;
    final nav = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
    nav.push(route);
    try {
      return await action();
    } finally {
      if (route.isActive) {
        nav.removeRoute(route);
      }
    }
  }

  bool _useSystemAppToOpen(String fileName, int byteLength) {
    final name = fileName.trim().toLowerCase();
    final isPdf = name.endsWith('.pdf') || chatPayloadIsPdf(null, fileName);
    if (isPdf && (isDesktopCommOnly || byteLength > _inAppPdfMaxBytes)) {
      return true;
    }
    if (!isDesktopCommOnly) return false;
    return name.endsWith('.xlsx') ||
        name.endsWith('.xls') ||
        name.endsWith('.docx') ||
        name.endsWith('.doc') ||
        name.endsWith('.pptx') ||
        name.endsWith('.ppt');
  }

  Future<void> _openDoc(NativeKbDocument doc) async {
    final share = KbChatDocShare.fromDocument(doc);
    final openId = share.openDocId;
    if (openId.isEmpty) {
      _toast('文档无效，无法打开', error: true);
      return;
    }
    final displayName = doc.fileName.trim().isNotEmpty
        ? doc.fileName.trim()
        : (doc.title.trim().isNotEmpty ? doc.title.trim() : '文档');

    // Markdown 仍走知识库内预览页（可读性更好）。
    if (_isMarkdownDoc(doc, displayName)) {
      widget.onOpenDoc(doc);
      return;
    }

    try {
      final downloaded = await _withOpenProgress(
        () => _service.downloadDocumentBytes(docId: openId, hint: doc),
      );
      if (downloaded == null || !mounted) return;
      final fileName = downloaded.fileName.trim().isNotEmpty
          ? downloaded.fileName.trim()
          : displayName;
      final localPath = await file_dl.saveBytesAsCachedFile(
        downloaded.bytes,
        'kb-home-$openId',
        fileName,
      );
      if (!mounted) return;
      if (localPath == null || localPath.isEmpty) {
        _toast('保存文件失败', error: true);
        return;
      }

      final isPdf = chatPayloadIsPdf(null, fileName);
      if (_useSystemAppToOpen(fileName, downloaded.bytes.length)) {
        await file_dl.openLocalFile(localPath);
        if (!mounted) return;
        _toast(
          isPdf && downloaded.bytes.length > _inAppPdfMaxBytes
              ? '文件较大，已用系统应用打开'
              : '已用系统应用打开',
        );
        return;
      }

      if (isPdf) {
        try {
          await showChatPdfPreview(
            context: context,
            service: _chatService,
            payload: <String, dynamic>{
              'fileName': fileName,
              'mimeType': 'application/pdf',
              'size': downloaded.bytes.length,
              'objectKey': 'kb-home-$openId',
            },
            fileName: fileName,
            initialBytes: downloaded.bytes,
            saveToKbSession: widget.session,
            saveToDriveSession: widget.session,
          );
          return;
        } catch (_) {
          await file_dl.openLocalFile(localPath);
          if (mounted) _toast('应用内预览失败，已用系统应用打开');
          return;
        }
      }

      await showChatFilePreview(
        context: context,
        service: _chatService,
        payload: <String, dynamic>{
          'fileName': fileName,
          'mimeType': lookupMimeType(fileName) ?? 'application/octet-stream',
          'size': downloaded.bytes.length,
          'objectKey': 'kb-home-$openId',
        },
        fileName: fileName,
        initialLocalPath: localPath,
        saveToKbSession: widget.session,
        saveToDriveSession: widget.session,
      );
    } catch (e, st) {
      debugPrint('[KB] openDoc failed: $e\n$st');
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _toast(friendlyErrorText(e, fallback: '打开失败，请稍后重试'), error: true);
      });
    }
  }

  Future<void> _forwardDoc(NativeKbDocument doc) async {
    if (_forwardingDocId != null || _savingDriveDocId != null) return;
    final share = KbChatDocShare.fromDocument(doc);
    if (share.openDocId.isEmpty) {
      _toast('文档无效，暂无法转发', error: true);
      return;
    }
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: _chatService,
      title: '转发至',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;

    setState(() => _forwardingDocId = doc.id);
    try {
      final downloaded = await _service.downloadDocumentBytes(
        docId: share.openDocId,
        hint: doc,
      );
      final fileName = downloaded.fileName.trim().isNotEmpty
          ? downloaded.fileName.trim()
          : (doc.fileName.trim().isNotEmpty
                ? doc.fileName.trim()
                : share.title);
      final mimeType =
          lookupMimeType(fileName) ??
          lookupMimeType('file.${doc.fileExtension}') ??
          'application/octet-stream';
      await _chatService.sendFile(
        conversationId: conversationId,
        bytes: downloaded.bytes,
        fileName: fileName,
        mimeType: mimeType,
        extraPayload: share.toMessagePayload(),
      );
      if (!mounted) return;
      _toast('已转发到会话');
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyErrorText(e, fallback: '转发失败，请稍后重试'), error: true);
    } finally {
      if (mounted) setState(() => _forwardingDocId = null);
    }
  }

  Future<void> _saveDocToDrive(NativeKbDocument doc) async {
    if (_savingDriveDocId != null || _forwardingDocId != null) return;
    final share = KbChatDocShare.fromDocument(doc);
    if (share.openDocId.isEmpty) {
      _toast('文档无效，暂无法存入微盘', error: true);
      return;
    }
    setState(() => _savingDriveDocId = doc.id);
    try {
      final downloaded = await _service.downloadDocumentBytes(
        docId: share.openDocId,
        hint: doc,
      );
      if (!mounted) return;
      final fileName = downloaded.fileName.trim().isNotEmpty
          ? downloaded.fileName.trim()
          : (doc.fileName.trim().isNotEmpty
                ? doc.fileName.trim()
                : share.title);
      final mimeType =
          lookupMimeType(fileName) ??
          lookupMimeType('file.${doc.fileExtension}') ??
          'application/octet-stream';
      final sourceKey = _driveSourceKeyForDoc(doc);
      final ok = await saveBytesToDrive(
        context: context,
        session: widget.session,
        bytes: downloaded.bytes,
        fileName: fileName,
        mimeType: mimeType,
        sourceKey: sourceKey,
      );
      if (ok && sourceKey.isNotEmpty && mounted) {
        setState(() => _driveSavedDocKeys.add(sourceKey));
      }
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyErrorText(e, fallback: '存入微盘失败，请稍后重试'), error: true);
    } finally {
      if (mounted) setState(() => _savingDriveDocId = null);
    }
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
                onRefresh: () => _load(silent: true),
                child: ListView(
                  controller: _scroll,
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
                          _sectionLabel('我的', '文档', count: '$_listTotal 篇'),
                          const SizedBox(height: 8),
                          _buildDocumentSearch(),
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
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
          colors: [Color(0xFF8B7BE0), Color(0xFF7B5CD8), Color(0xFF5B3FB0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -36,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -50,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
              const Text(
                'DUNES KNOWLEDGE · 企业知识库',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                '知识库',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '公司制度 / 流程 SOP / 合同模板 / 法务条款 / 财务规则 — 一处查全',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _heroStat('${_displayDocumentCount}', '文档'),
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 8,
            letterSpacing: 0.5,
          ),
        ),
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
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: const Text('同步 RAGFlow', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _syncStatus,
              style: const TextStyle(fontSize: 10, color: DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String accent, String title, {String? count}) {
    return Row(
      children: [
        Text(
          accent,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7B5CD8),
          ),
        ),
        Text(
          ' · $title',
          style: const TextStyle(fontSize: 11, color: DunesColors.text2),
        ),
        const Expanded(
          child: Divider(
            indent: 8,
            endIndent: 8,
            color: DunesColors.borderSoft,
          ),
        ),
        if (count != null)
          Text(
            count,
            style: const TextStyle(fontSize: 10, color: DunesColors.text3),
          ),
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
          if (_supportsDesktopDrop)
            DropTarget(
              enable: ready && !_uploading,
              onDragEntered: (_) {
                if (!_dragging) setState(() => _dragging = true);
              },
              onDragExited: (_) {
                if (_dragging) setState(() => _dragging = false);
              },
              onDragDone: (d) => unawaited(_onDesktopDrop(d)),
              child: _buildUploadZone(ready),
            )
          else
            _buildUploadZone(ready),
          if (_uploading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              value: KbUploadCoordinator.instance.progress,
            ),
            const SizedBox(height: 6),
            Text(
              _uploadProgress ?? '正在上传并解析…',
              style: const TextStyle(fontSize: 10, color: DunesColors.text3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadZone(bool ready) {
    final highlight = _dragging && ready && !_uploading;
    return InkWell(
      onTap: ready && !_uploading ? _pickAndUpload : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: highlight
              ? _kbAccent.withValues(alpha: 0.08)
              : const Color(0xFFF7F6F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? _kbAccent : DunesColors.borderSoft,
            width: highlight ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.upload_file,
              color: ready ? _kbAccent : DunesColors.text3,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              _supportsDesktopDrop
                  ? (highlight
                        ? '松开以上传文件（一次最多 $_maxKbUploadBatch 个）'
                        : '点击选择，或拖拽文件到此处（一次最多 $_maxKbUploadBatch 个）')
                  : '点击选择文档 / 图片 / 语音等文件',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: highlight ? _kbAccent : null,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ready
                  ? '支持 $kChatKbUploadSupportLabel · 上传后自动解析'
                  : 'Nova 知识库未就绪，请稍后重试',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }

  int get _displayDocumentCount {
    final fromSummary = _summary?.documentCount ?? 0;
    if (_search.text.trim().isNotEmpty) return _listTotal;
    return fromSummary > _listTotal ? fromSummary : _listTotal;
  }

  Widget _buildDocList() {
    final docs = _pageDocs;
    if (docs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DunesColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: DunesColors.text3),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                _search.text.trim().isEmpty ? '暂无文档，请先上传' : '未找到匹配的文档',
                style: TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final doc in docs)
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => unawaited(_openDoc(doc)),
              child: Container(
                key: ValueKey(doc.id),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
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
                      child: const Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: DunesColors.text2,
                      ),
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
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0EEE8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (doc.fileExtension.isEmpty
                                          ? 'DOC'
                                          : doc.fileExtension)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                doc.statusLabel,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: DunesColors.text3,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final driveKey = _driveSourceKeyForDoc(doc);
                        final driveSaved =
                            driveKey.isNotEmpty &&
                            _driveSavedDocKeys.contains(driveKey);
                        return Tooltip(
                          message: driveSaved ? '再次存入微盘' : '存入微盘',
                          child: Material(
                            color: _driveBlueSoft,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap:
                                  _savingDriveDocId == doc.id ||
                                      _forwardingDocId != null
                                  ? null
                                  : () => unawaited(_saveDocToDrive(doc)),
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child: _savingDriveDocId == doc.id
                                    ? const Padding(
                                        padding: EdgeInsets.all(7),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _driveBlue,
                                        ),
                                      )
                                    : Icon(
                                        driveSaved
                                            ? Icons.folder_copy_outlined
                                            : Icons.folder_shared_outlined,
                                        size: 15,
                                        color: _driveBlue,
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: DunesColors.brandPurpleSoft,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap:
                            _forwardingDocId == doc.id ||
                                _savingDriveDocId != null
                            ? null
                            : () => unawaited(_forwardDoc(doc)),
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: _forwardingDocId == doc.id
                              ? const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DunesColors.brandPurple,
                                  ),
                                )
                              : const Icon(
                                  Icons.ios_share_rounded,
                                  size: 15,
                                  color: DunesColors.brandPurple,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: DunesColors.coralSoft,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => _deleteDoc(doc),
                        borderRadius: BorderRadius.circular(8),
                        child: const SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: DunesColors.coral,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_loadingMore) ...[
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ] else if (_hasMore && _pageDocs.length >= _pageSize) ...[
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '下滑加载更多',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: DunesColors.text3),
            ),
          ),
        ],
      ],
    );
  }

  void _onKeywordChanged(String value) {
    _searchDebounce?.cancel();
    final keyword = value.trim();
    setState(() => _searching = keyword.isNotEmpty);
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_load(silent: true));
    });
  }

  Widget _buildDocumentSearch() {
    return TextField(
      controller: _search,
      onChanged: _onKeywordChanged,
      decoration: InputDecoration(
        hintText: '搜索文档名称、文件类型…',
        prefixIcon: const Icon(Icons.search_rounded, size: 19),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _search.clear();
                  _onKeywordChanged('');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DunesColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: DunesColors.border),
        ),
      ),
    );
  }
}
