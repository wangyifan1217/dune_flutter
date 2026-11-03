import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/util/native_permissions.dart';
import '../chat/chat_file_type_icon.dart';
import '../chat/file_download.dart' as file_dl;
import '../shell/dunes_toast.dart';
import 'xflow_file_open.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

class XflowUploadField extends StatefulWidget {
  const XflowUploadField({
    super.key,
    required this.field,
    required this.items,
    required this.service,
    required this.onChanged,
  });

  final XflowField field;
  final List<Map<String, dynamic>> items;
  final XflowService service;
  final void Function(List<Map<String, dynamic>> items) onChanged;

  @override
  State<XflowUploadField> createState() => _XflowUploadFieldState();
}

class _XflowUploadFieldState extends State<XflowUploadField> {
  bool _picking = false;
  bool _dragging = false;
  bool _downloadingTemplate = false;
  final _recognizingIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recognizeExistingInvoices());
    });
  }

  static const _meta = <String, Map<String, dynamic>>{
    'planFiles': {
      'variant': 'plan',
      'hint': 'JPG / PNG / HEIC / PDF · 最多 5 个',
      'title': '点击选择或拖拽图片 / PDF',
      'desc': '单个不超过 10MB · 优先图片',
      'extensions': ['jpg', 'jpeg', 'png', 'heic', 'heif', 'pdf'],
      'maxBytes': 10 * 1024 * 1024,
      'icon': Icons.add_photo_alternate_outlined,
    },
    // 与 planFiles 同义：模板里「产品文件」常用此 key
    'productFiles': {
      'variant': 'plan',
      'hint': 'JPG / PNG / HEIC / PDF · 最多 5 个',
      'title': '点击选择或拖拽产品文件',
      'desc': '单个不超过 10MB · 图片 / PDF',
      'extensions': ['jpg', 'jpeg', 'png', 'heic', 'heif', 'pdf'],
      'maxBytes': 10 * 1024 * 1024,
      'icon': Icons.add_photo_alternate_outlined,
    },
    'contractFiles': {
      'variant': 'contract',
      'hint': 'PDF / DOCX · 最多 5 个',
      'title': '上传供货商/渠道商务合同',
      'desc': '审批层单独查看 · 与方案附件分开',
      'extensions': ['pdf', 'doc', 'docx'],
      'maxBytes': 20 * 1024 * 1024,
      'icon': Icons.file_present_outlined,
    },
  };

  Map<String, dynamic> get _uploadMeta {
    final base = _meta[widget.field.key] ?? const {};
    final fromField = _extensionsFromField(widget.field);
    final extensions = fromField.isNotEmpty
        ? fromField
        : (base['extensions'] as List?)?.cast<String>() ?? const <String>[];
    return {
      'variant': base['variant'] ?? 'plan',
      'hint': _hintWithMaxFiles(base['hint'] as String?),
      'title': base['title'] ?? '点击选择或拖拽文件',
      'desc': base['desc'] ?? '上传后自动保存到文件服务器',
      'extensions': extensions,
      'maxBytes': base['maxBytes'] ?? 20 * 1024 * 1024,
      'icon': base['icon'] ?? Icons.upload_outlined,
    };
  }

  /// 文案里的「最多 N 个」跟字段 [maxFiles] 走，避免后端配 10、界面仍写 5。
  String _hintWithMaxFiles(String? baseHint) {
    final max = _maxFiles;
    if (baseHint == null || baseHint.trim().isEmpty) return '最多 $max 个';
    return baseHint.replaceFirst(RegExp(r'最多\s*\d+\s*个'), '最多 $max 个');
  }

  List<String> _extensionsFromField(XflowField field) {
    final raw = field.raw['accept'] ?? field.raw['extensions'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => e.toString().trim().toLowerCase().replaceFirst('.', ''))
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  int get _maxFiles {
    final v = widget.field.raw['maxFiles'];
    if (v is num) {
      final n = v.toInt();
      return n > 0 ? n : 5;
    }
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null && n > 0) return n;
    }
    return 5;
  }

  String get _label {
    if (widget.field.label.trim().isNotEmpty) return widget.field.label.trim();
    if (widget.field.key == 'contractFiles') return '商务合同附件';
    if (widget.field.key == 'planFiles' || widget.field.key == 'productFiles') {
      return '产品文件';
    }
    return widget.field.key;
  }

  XflowUploadTemplate? get _template => widget.field.uploadTemplate;

  /// 报销发票：上传后识别发票号码和金额、查重、累计（字段 meta.invoiceOcr=true）。
  bool get _invoiceMode => xflowIsInvoiceField(widget.field);

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  Future<void> _downloadTemplate() async {
    final template = _template;
    if (template == null || _downloadingTemplate) return;
    setState(() => _downloadingTemplate = true);
    try {
      final file = await widget.service.downloadConfiguredFile(
        path: template.url,
        fileName: template.name,
      );
      if (!mounted) return;
      final path = await file_dl.saveBytesAsFile(file.bytes, file.fileName);
      if (!mounted) return;
      if (kIsWeb) {
        _toast('已开始下载 ${file.fileName}');
        return;
      }
      if (path == null || path.isEmpty) {
        _toast('保存失败');
        return;
      }
      await file_dl.openLocalFile(path);
      if (!mounted) return;
      _toast('已打开 ${file.fileName}');
    } catch (e) {
      if (!mounted) return;
      _toast('下载失败：${friendlyErrorText(e, fallback: '无法下载模板')}');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _pickFiles() async {
    if (_picking) return;
    final active = widget.items.where((it) => it['status'] != 'error').length;
    final room = _maxFiles - active;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个文件');
      return;
    }
    setState(() => _picking = true);
    try {
      final meta = _uploadMeta;
      final exts = (meta['extensions'] as List).cast<String>();
      if (_needsPhotosPermission(exts) && !await ensurePhotosPermission()) {
        final status = await Permission.photos.status;
        _toast(photosPermissionHint(status));
        return;
      }
      final picked = await _openFilesWithFallback(exts);
      if (picked.isEmpty) return;
      await _ingestFiles(picked, room: room);
    } catch (e) {
      _toast('选择文件失败：${friendlyErrorText(e, fallback: '无法打开文件选择器，请重试')}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (_picking) return;
    final active = widget.items.where((it) => it['status'] != 'error').length;
    final room = _maxFiles - active;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个文件');
      return;
    }
    setState(() {
      _picking = true;
      _dragging = false;
    });
    final accessed = <Uint8List>[];
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        // macOS 沙盒：开启 security-scoped 访问，避免拖入后读文件失败。
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        _toast('请拖入文件（不支持文件夹）');
        return;
      }
      await _ingestFiles(files, room: room);
    } catch (e) {
      _toast('拖拽上传失败：${friendlyErrorText(e, fallback: '无法读取拖入的文件')}');
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _ingestFiles(List<XFile> picked, {required int room}) async {
    final meta = _uploadMeta;
    final exts = (meta['extensions'] as List).cast<String>();
    final next = List<Map<String, dynamic>>.from(widget.items);
    var accepted = 0;
    for (final file in picked) {
      if (accepted >= room) {
        _toast('最多上传 $_maxFiles 个文件');
        break;
      }
      final name = file.name;
      if (!_isAllowedExtension(name, exts)) {
        _toast('$name 类型不支持');
        continue;
      }
      final bytes = await file.readAsBytes();
      final maxBytes = meta['maxBytes'] as int;
      if (bytes.length > maxBytes) {
        _toast('$name 超过大小限制');
        continue;
      }
      final id = 'uf-${DateTime.now().millisecondsSinceEpoch}-${next.length}';
      final item = <String, dynamic>{
        'id': id,
        'fileName': name,
        'size': bytes.length,
        'mimeType': lookupMimeType(name, headerBytes: bytes) ?? '',
        'status': 'uploading',
        'progress': 0,
      };
      next.add(item);
      accepted++;
      widget.onChanged(next);
      await _uploadOne(next, item, bytes, name);
    }
  }

  bool _isAllowedExtension(String fileName, List<String> exts) {
    if (exts.isEmpty) return true;
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) return false;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return exts.any((e) => e.toLowerCase() == ext);
  }

  Future<List<XFile>> _openFilesWithFallback(List<String> exts) async {
    final typeGroup = XTypeGroup(
      label: 'files',
      extensions: exts,
      mimeTypes: _mimeTypesFor(exts),
    );
    try {
      return await openFiles(acceptedTypeGroups: [typeGroup]);
    } catch (_) {
      // iOS 上部分类型组合会触发平台层异常，降级到仅后缀过滤可提升兼容性。
      try {
        final fallback = XTypeGroup(label: 'files', extensions: exts);
        return await openFiles(acceptedTypeGroups: [fallback]);
      } catch (_) {
        // 最后兜底：不带过滤，避免 iOS 因类型声明导致选择器无法弹出。
        return openFiles();
      }
    }
  }

  bool _needsPhotosPermission(List<String> exts) {
    // 网页没有 dart:io 的 Platform，一查就会抛错，文件选择器也就打不开。
    if (kIsWeb || !Platform.isIOS) return false;
    const imageExts = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'gif', 'webp'};
    return exts.any((ext) => imageExts.contains(ext.toLowerCase()));
  }

  List<String> _mimeTypesFor(List<String> exts) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return exts
        .map((e) => map[e.toLowerCase()] ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _uploadOne(
    List<Map<String, dynamic>> list,
    Map<String, dynamic> item,
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final data = await widget.service.uploadProposalFile(
        bytes: bytes,
        fileName: fileName,
        onProgress: (pct) {
          item['progress'] = pct;
          if (mounted) setState(() {});
          widget.onChanged(List<Map<String, dynamic>>.from(list));
        },
      );
      item
        ..['status'] = 'done'
        ..['progress'] = 100
        ..['url'] = data['url'] ?? ''
        ..['objectKey'] = data['objectKey'] ?? data['url'] ?? ''
        ..['backend'] = data['backend'] ?? '';
    } catch (e) {
      item
        ..['status'] = 'error'
        ..['error'] = friendlyErrorText(e, fallback: '上传失败，请稍后重试');
    }
    if (mounted) setState(() {});
    widget.onChanged(List<Map<String, dynamic>>.from(list));
    if (_invoiceMode && item['status'] == 'done') {
      await _recognizeInvoice(list, item, bytes, fileName);
    }
  }

  /// 打开表单时，已经传过的发票不会再走上传回调，这里补一次识别。
  Future<void> _recognizeExistingInvoices() async {
    if (!_invoiceMode || !mounted) return;
    final list = [
      for (final item in widget.items) Map<String, dynamic>.from(item),
    ];
    for (final item in list) {
      final status = '${item['status'] ?? ''}';
      if (status == 'uploading' || status == 'error') continue;
      if ('${item['invoiceStatus'] ?? ''}'.isNotEmpty) continue;
      final id = '${item['id'] ?? item['objectKey'] ?? item['fileName'] ?? ''}';
      if (id.isEmpty || !_recognizingIds.add(id)) continue;
      final name = '${item['fileName'] ?? item['name'] ?? 'invoice.pdf'}'.trim();
      try {
        final url = await widget.service.resolveFileUrl(item);
        if (url.isEmpty || !mounted) continue;
        final response = await http.get(Uri.parse(url));
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        if (!mounted || response.bodyBytes.isEmpty) continue;
        await _recognizeInvoice(
          list,
          item,
          response.bodyBytes,
          name.isEmpty ? 'invoice.pdf' : name,
        );
      } catch (_) {}
    }
  }

  Future<void> _recognizeInvoice(
    List<Map<String, dynamic>> list,
    Map<String, dynamic> item,
    Uint8List bytes,
    String fileName,
  ) async {
    item['invoiceStatus'] = 'recognizing';
    if (mounted) setState(() {});
    widget.onChanged(List<Map<String, dynamic>>.from(list));
    try {
      final data = await widget.service.recognizeInvoice(
        bytes: bytes,
        fileName: fileName,
        objectKey: '${item['objectKey'] ?? ''}',
      );
      final invoice = data['invoice'];
      item
        ..['invoiceStatus'] = 'done'
        ..['invoice'] = invoice is Map ? Map<String, dynamic>.from(invoice) : {}
        ..['invoiceRecordId'] = invoice is Map ? invoice['recordId'] : null
        ..['invoiceBlocked'] = data['blocked'] == true
        ..['invoiceUnrecognized'] = data['unrecognized'] == true
        ..['invoiceMessage'] = '${data['message'] ?? ''}';
      if (data['blocked'] == true) {
        _toast('$fileName：${data['message'] ?? '这张发票不能提交'}');
      }
    } catch (e) {
      // 识别服务失败也能提交，按识别不了处理，审批时人工核对。
      item
        ..['invoiceStatus'] = 'error'
        ..['invoiceBlocked'] = false
        ..['invoiceUnrecognized'] = true
        ..['invoiceMessage'] =
            '识别失败（${friendlyErrorText(e, fallback: '服务暂不可用')}），可以提交，审批时需人工核对';
    }
    if (mounted) setState(() {});
    widget.onChanged(List<Map<String, dynamic>>.from(list));
  }

  void _remove(String id) {
    final next = widget.items
        .where((it) => it['id']?.toString() != id)
        .toList(growable: false);
    widget.onChanged(next);
    setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    showDunesToast(
      context,
      msg,
      kind: dunesToastLooksLikeError(msg)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _uploadMeta;
    final variant = meta['variant'] as String;
    final isContract = variant == 'contract';
    final dropChild = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _picking ? null : _pickFiles,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isContract
                  ? [
                      DunesColors.resolve(
                        context,
                        Color(0xFFF5EBE0),
                        role: DunesColorRole.surface,
                      ),
                      DunesColors.resolve(
                        context,
                        Color(0xFFEFE2D2),
                        role: DunesColorRole.surface,
                      ),
                    ]
                  : [
                      DunesColors.resolve(
                        context,
                        Color(0xFFF8F1E8),
                        role: DunesColorRole.surface,
                      ),
                      DunesColors.resolve(
                        context,
                        Color(0xFFF3EBE0),
                        role: DunesColorRole.surface,
                      ),
                    ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _dragging
                  ? DunesColors.resolve(
                      context,
                      const Color(0xFF3B82F6),
                      role: DunesColorRole.border,
                    )
                  : isContract
                  ? DunesColors.resolve(
                      context,
                      const Color(0x6BBE965A),
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0x59A0825A),
                      role: DunesColorRole.border,
                    ),
              width: _dragging ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                meta['icon'] as IconData,
                size: 30,
                color: _dragging
                    ? DunesColors.resolve(context, const Color(0xFF2563EB))
                    : DunesColors.resolve(context, DunesColors.text3),
              ),
              const SizedBox(height: 10),
              Text(
                _dragging ? '松开即可上传' : meta['title'] as String,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _dragging
                      ? DunesColors.resolve(context, const Color(0xFF1D4ED8))
                      : DunesColors.resolve(context, DunesColors.text2),
                  height: 1.45,
                  context: context,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                meta['desc'] as String,
                textAlign: TextAlign.center,
                style: DunesTypography.mono(
                  fontSize: 9,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  letterSpacing: 0.03 * 9,
                  height: 1.5,
                  context: context,
                ),
              ),
              if (_picking) ...[
                const SizedBox(height: 10),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: _label,
                    style: DunesTypography.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                    children: [
                      TextSpan(
                        text: ' ${meta['hint']}',
                        style: DunesTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_template != null)
                TextButton(
                  onPressed: _downloadingTemplate
                      ? null
                      : () {
                          unawaited(_downloadTemplate());
                        },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _downloadingTemplate
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _template!.label,
                          style: DunesTypography.sans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFF2563EB),
                            ),
                            context: context,
                          ),
                        ),
                ),
            ],
          ),
        ),
        if (_supportsDesktopDrop)
          DropTarget(
            onDragEntered: (_) {
              if (!_picking) setState(() => _dragging = true);
            },
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) {
              unawaited(_onDesktopDrop(detail));
            },
            child: dropChild,
          )
        else
          dropChild,
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final item in widget.items)
            _XflowUploadFileRow(
              item: item,
              service: widget.service,
              invoiceMode: _invoiceMode,
              onRemove: () => _remove(item['id']?.toString() ?? ''),
            ),
          if (_invoiceMode) _InvoiceSummary(items: widget.items),
        ],
      ],
    );
  }
}

class _XflowUploadFileRow extends StatefulWidget {
  const _XflowUploadFileRow({
    required this.item,
    required this.service,
    required this.onRemove,
    this.invoiceMode = false,
  });

  final Map<String, dynamic> item;
  final XflowService service;
  final VoidCallback onRemove;
  final bool invoiceMode;

  @override
  State<_XflowUploadFileRow> createState() => _XflowUploadFileRowState();
}

class _XflowUploadFileRowState extends State<_XflowUploadFileRow> {
  bool _busy = false;
  bool _downloaded = false;
  bool _statusChecked = false;

  Map<String, dynamic> get item => widget.item;

  String get _status => (item['status'] ?? 'done').toString();
  String get _fileName => xflowAttachmentFileName(item);
  bool get _canOpen =>
      _status == 'done' && xflowAttachmentCacheKey(item).isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDownloaded());
  }

  @override
  void didUpdateWidget(covariant _XflowUploadFileRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (xflowAttachmentCacheKey(oldWidget.item) !=
            xflowAttachmentCacheKey(item) ||
        (oldWidget.item['status'] ?? '') != (item['status'] ?? '')) {
      unawaited(_refreshDownloaded());
    }
  }

  Future<void> _refreshDownloaded() async {
    if (!_canOpen || kIsWeb) {
      if (mounted) {
        setState(() {
          _downloaded = false;
          _statusChecked = true;
        });
      }
      return;
    }
    final ok = await isXflowAttachmentDownloaded(item);
    if (!mounted) return;
    setState(() {
      _downloaded = ok;
      _statusChecked = true;
    });
  }

  Future<void> _open() async {
    if (!_canOpen || _busy) return;
    setState(() => _busy = true);
    try {
      await openXflowAttachment(
        context: context,
        service: widget.service,
        item: item,
        preferPreview: true,
      );
      await _refreshDownloaded();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (!_canOpen || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await downloadXflowAttachment(
        context: context,
        service: widget.service,
        item: item,
        force: _downloaded,
        reveal: true,
      );
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        setState(() => _downloaded = true);
      } else {
        await _refreshDownloaded();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatSize(dynamic bytes) {
    final n = bytes is num ? bytes.toInt() : int.tryParse('$bytes') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final name = _fileName;
    final progress = item['progress'] is num
        ? (item['progress'] as num).toInt()
        : 0;
    final sizeText = _formatSize(item['size']);
    final metaText = switch (status) {
      'uploading' => '上传中 $progress%',
      'error' => (item['error'] ?? '上传失败').toString(),
      _ => [
        sizeText,
        if (_statusChecked && _downloaded) '已下载',
      ].where((e) => e.isNotEmpty).join(' · '),
    };
    final invoiceLine = widget.invoiceMode ? xflowInvoiceLine(item) : '';
    final invoiceBlocked =
        widget.invoiceMode && status == 'done' && xflowInvoiceBlocked(item);
    final invoiceUnrecognized =
        widget.invoiceMode &&
        status == 'done' &&
        !invoiceBlocked &&
        xflowInvoiceUnrecognized(item);
    final invoiceMessage = invoiceBlocked || invoiceUnrecognized
        ? xflowInvoiceProblem(item)
        : '';
    final invoiceMessageColor = invoiceBlocked
        ? DunesColors.coral
        : const Color(0xFFB45309);
    Color borderColor = DunesColors.resolve(context, DunesColors.borderSoft);
    Color bg = DunesColors.resolve(
      context,
      DunesColors.bgSoft,
      role: DunesColorRole.surface,
    );
    if (status == 'uploading') {
      borderColor = DunesColors.resolve(
        context,
        DunesColors.accent,
      ).withValues(alpha: 0.25);
      bg = DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      );
    } else if (status == 'error' || invoiceBlocked) {
      borderColor = DunesColors.resolve(
        context,
        DunesColors.coral,
      ).withValues(alpha: 0.35);
      bg = DunesColors.resolve(
        context,
        const Color(0xFFFFF8F7),
        role: DunesColorRole.surface,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _canOpen && !_busy ? _open : null,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
          decoration: BoxDecoration(
            color: DunesColors.resolveNullable(
              context,
              bg,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              ChatFileTypeIcon(fileName: name, size: 32),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.resolve(context, DunesColors.text),
                        context: context,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metaText,
                      style: DunesTypography.mono(
                        fontSize: 9.5,
                        color: DunesColors.resolve(context, DunesColors.text3),
                        context: context,
                      ),
                    ),
                    if (invoiceLine.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          invoiceLine,
                          style: DunesTypography.sans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text2,
                            ),
                            context: context,
                          ),
                        ),
                      ),
                    if (invoiceMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          invoiceMessage,
                          style: DunesTypography.sans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: DunesColors.resolve(
                              context,
                              invoiceMessageColor,
                            ),
                            context: context,
                          ),
                        ),
                      ),
                    if (status == 'uploading' || status == 'error')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: status == 'error' ? 1 : progress / 100,
                            minHeight: 3,
                            backgroundColor: DunesColors.resolve(
                              context,
                              DunesColors.borderSoft,
                              role: DunesColorRole.surface,
                            ),
                            color: status == 'error'
                                ? DunesColors.resolve(
                                    context,
                                    DunesColors.coral,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    DunesColors.accent,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_canOpen)
                IconButton(
                  tooltip: _downloaded ? '重新下载' : '下载到本地',
                  icon: Icon(
                    Icons.download_outlined,
                    size: 17,
                    color: _downloaded
                        ? DunesColors.resolve(context, const Color(0xFF3B82F6))
                        : DunesColors.resolve(context, DunesColors.text3),
                  ),
                  onPressed: _busy ? null : _download,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(28, 28),
                    padding: EdgeInsets.zero,
                  ),
                ),
              IconButton(
                tooltip: '移除',
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: DunesColors.resolve(context, DunesColors.text3),
                ),
                onPressed: widget.onRemove,
                style: IconButton.styleFrom(
                  minimumSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发票合计：已识别、能提交的发票张数和价税合计；不能提交的单独计数。
class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final summary = xflowInvoiceSummary(items);
    final parts = <String>[
      '已识别 ${summary.count} 张，合计 ¥${summary.total.toStringAsFixed(2)}',
      if (summary.unrecognized > 0) '${summary.unrecognized} 张未识别（不计入合计）',
      if (summary.pending > 0) '${summary.pending} 张识别中',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parts.join(' · '),
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          if (summary.blocked > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${summary.blocked} 张发票已报销过或重复上传，不能提交，请删除后再提交',
                style: DunesTypography.sans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.coral),
                  context: context,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- 报销发票（字段 meta.invoiceOcr=true）----

bool xflowIsInvoiceField(XflowField field) {
  final meta = field.raw['meta'];
  if (meta is! Map) return false;
  final v = meta['invoiceOcr'];
  return v == true || '$v'.toLowerCase() == 'true' || v == 1;
}

Map<String, dynamic> _invoiceOf(Map<String, dynamic> item) {
  final v = item['invoice'];
  return v is Map ? Map<String, dynamic>.from(v) : const {};
}

double? _invoiceTotal(Map<String, dynamic> item) {
  final v = _invoiceOf(item)['total'];
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.replaceAll(',', '').trim());
}

/// 一张发票的识别摘要：发票号 · 日期 · 销售方 · 金额。
String xflowInvoiceLine(Map<String, dynamic> item) {
  if (item['invoiceStatus'] == 'recognizing') return '正在识别发票…';
  final inv = _invoiceOf(item);
  final no = '${inv['invoiceNo'] ?? ''}'.trim();
  if (no.isEmpty) return '';
  final total = _invoiceTotal(item);
  return [
    '发票号 $no',
    '${inv['invoiceDate'] ?? ''}'.trim(),
    '${inv['sellerName'] ?? ''}'.trim(),
    if (total != null) '¥${total.toStringAsFixed(2)}',
  ].where((e) => e.isNotEmpty).join(' · ');
}

/// 这张发票能不能提交：只有重复报销（已在审批中 / 已通过的单据里）不能提交。
bool xflowInvoiceBlocked(Map<String, dynamic> item) {
  if ('${item['status'] ?? 'done'}' != 'done') return false;
  if (item['invoiceStatus'] == 'recognizing') return false;
  return item['invoiceBlocked'] == true;
}

/// 识别不了（扫描件、图片版 PDF、识别服务失败）：可以提交，不计入合计，审批时人工核对。
bool xflowInvoiceUnrecognized(Map<String, dynamic> item) {
  if ('${item['status'] ?? 'done'}' != 'done') return false;
  if (item['invoiceStatus'] == 'recognizing') return false;
  if (item['invoiceUnrecognized'] == true) return true;
  final id = item['invoiceRecordId'] ?? _invoiceOf(item)['recordId'];
  if (id == null || '$id'.isEmpty) return true;
  return '${_invoiceOf(item)['invoiceNo'] ?? ''}'.trim().isEmpty ||
      _invoiceTotal(item) == null;
}

const kXflowInvoiceUnrecognizedHint =
    '未能自动识别（可能是扫描件或图片版 PDF），可以提交，金额不计入发票合计，审批时需人工核对';

String xflowInvoiceProblem(Map<String, dynamic> item) {
  final msg = '${item['invoiceMessage'] ?? ''}'.trim();
  if (msg.isNotEmpty) return msg;
  if (xflowInvoiceBlocked(item)) return '这张发票已报销过，不能重复提交';
  return kXflowInvoiceUnrecognizedHint;
}

class XflowInvoiceSummary {
  const XflowInvoiceSummary(
    this.count,
    this.total,
    this.blocked,
    this.pending, [
    this.unrecognized = 0,
  ]);
  final int count;
  final double total;
  final int blocked;
  final int pending;
  final int unrecognized;
}

XflowInvoiceSummary xflowInvoiceSummary(List<Map<String, dynamic>> items) {
  var count = 0, blocked = 0, pending = 0, unrecognized = 0;
  var total = 0.0;
  final seen = <String>{};
  for (final item in items) {
    final status = '${item['status'] ?? 'done'}';
    if (status == 'uploading' || item['invoiceStatus'] == 'recognizing') {
      pending++;
      continue;
    }
    if (status != 'done') continue;
    if (xflowInvoiceBlocked(item)) {
      blocked++;
      continue;
    }
    final no = '${_invoiceOf(item)['invoiceNo'] ?? ''}'.trim();
    if (no.isNotEmpty && !seen.add(no)) {
      // 同一张发票传了两次：只算一次，提交时会被拦下。
      blocked++;
      continue;
    }
    if (xflowInvoiceUnrecognized(item)) {
      unrecognized++;
      continue;
    }
    count++;
    total += _invoiceTotal(item) ?? 0;
  }
  return XflowInvoiceSummary(
    count,
    (total * 100).roundToDouble() / 100,
    blocked,
    pending,
    unrecognized,
  );
}

/// 提交前检查发票字段；有问题时返回提示，没问题返回 null。
String? xflowInvoiceSubmitProblem(
  List<XflowField> fields,
  Map<String, dynamic> values,
) {
  for (final field in fields) {
    if (!field.isUpload || !xflowIsInvoiceField(field)) continue;
    if (!field.visibleIn(values)) continue;
    final items = normalizeUploadItems(values[field.key]);
    final seen = <String, String>{};
    for (final item in items) {
      final name = xflowAttachmentFileName(item);
      if (item['invoiceStatus'] == 'recognizing') {
        return '发票「$name」还在识别，请稍候再提交';
      }
      if (xflowInvoiceBlocked(item)) {
        return '发票「$name」不能提交：${xflowInvoiceProblem(item)}';
      }
      final no = '${_invoiceOf(item)['invoiceNo'] ?? ''}'.trim();
      if (no.isEmpty) continue; // 识别不了的可以提交，审批时人工核对
      final prev = seen[no];
      if (prev != null) {
        return '发票 $no 重复上传了（「$prev」和「$name」），同一张发票只能报销一次';
      }
      seen[no] = name;
    }
  }
  return null;
}

List<Map<String, dynamic>> normalizeUploadItems(dynamic val) {
  if (val == null || val == '') return [];
  if (val is List) {
    return val
        .map((it) {
          if (it is Map<String, dynamic>) return Map<String, dynamic>.from(it);
          if (it is Map) return Map<String, dynamic>.from(it);
          if (it is String && it.trim().isNotEmpty) {
            return {
              'id': 'uf-${it.hashCode}',
              'fileName': it,
              'status': 'done',
              'progress': 100,
            };
          }
          return <String, dynamic>{};
        })
        .where((m) => m.isNotEmpty)
        .toList(growable: true);
  }
  return [];
}
