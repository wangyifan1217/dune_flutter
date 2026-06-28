import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../shell/dunes_toast.dart';
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
    final maxFiles = widget.field.raw['maxFiles'];
    return {
      'variant': base['variant'] ?? 'plan',
      'hint': base['hint'] ?? '最多 ${maxFiles ?? 5} 个',
      'title': base['title'] ?? '点击选择或拖拽文件',
      'desc': base['desc'] ?? '上传后自动保存到文件服务器',
      'extensions': base['extensions'] ?? const <String>[],
      'maxBytes': base['maxBytes'] ?? 20 * 1024 * 1024,
      'icon': base['icon'] ?? Icons.upload_outlined,
    };
  }

  int get _maxFiles {
    final v = widget.field.raw['maxFiles'];
    if (v is num) return v.toInt();
    return 5;
  }

  String get _label {
    if (widget.field.key == 'contractFiles') return '商务合同附件';
    return widget.field.label.isEmpty ? widget.field.key : widget.field.label;
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
      final picked = await _openFilesWithFallback(exts);
      if (picked.isEmpty) return;
      final next = List<Map<String, dynamic>>.from(widget.items);
      for (final file in picked.take(room)) {
        final bytes = await file.readAsBytes();
        final name = file.name;
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
        widget.onChanged(next);
        await _uploadOne(next, item, bytes, name);
      }
    } catch (e) {
      _toast('选择文件失败：${friendlyErrorText(e, fallback: '请检查相册/文件权限')}');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
      final fallback = XTypeGroup(label: 'files', extensions: exts);
      return openFiles(acceptedTypeGroups: [fallback]);
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text.rich(
            TextSpan(
              text: _label,
              style: DunesTypography.sans(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
              children: [
                TextSpan(
                  text: ' ${meta['hint']}',
                  style: DunesTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
        Material(
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
                      ? const [Color(0xFFF5EBE0), Color(0xFFEFE2D2)]
                      : const [Color(0xFFF8F1E8), Color(0xFFF3EBE0)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isContract
                      ? const Color(0x6BBE965A)
                      : const Color(0x59A0825A),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    meta['icon'] as IconData,
                    size: 30,
                    color: DunesColors.text3,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    meta['title'] as String,
                    textAlign: TextAlign.center,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text2,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    meta['desc'] as String,
                    textAlign: TextAlign.center,
                    style: DunesTypography.mono(
                      fontSize: 9,
                      color: DunesColors.text3,
                      letterSpacing: 0.03 * 9,
                      height: 1.5,
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
        ),
        if (widget.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final item in widget.items) _fileRow(item),
        ],
      ],
    );
  }

  Widget _fileRow(Map<String, dynamic> item) {
    final status = (item['status'] ?? 'done').toString();
    final name = (item['fileName'] ?? '未命名文件').toString();
    final progress = item['progress'] is num
        ? (item['progress'] as num).toInt()
        : 0;
    final metaText = switch (status) {
      'uploading' => '上传中 $progress%',
      'error' => (item['error'] ?? '上传失败').toString(),
      _ => _formatSize(item['size']),
    };
    Color borderColor = DunesColors.borderSoft;
    Color bg = DunesColors.bgSoft;
    if (status == 'uploading') {
      borderColor = DunesColors.accent.withValues(alpha: 0.25);
      bg = Colors.white;
    } else if (status == 'error') {
      borderColor = DunesColors.coral.withValues(alpha: 0.35);
      bg = const Color(0xFFFFF8F7);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Icon(_fileIcon(name), size: 16, color: DunesColors.accent),
          ),
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
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  metaText,
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    color: DunesColors.text3,
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
                        backgroundColor: DunesColors.borderSoft,
                        color: status == 'error'
                            ? DunesColors.coral
                            : DunesColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: DunesColors.text3),
            onPressed: () => _remove(item['id']?.toString() ?? ''),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'\.(jpg|jpeg|png|heic|heif|gif|webp)$').hasMatch(n)) {
      return Icons.image_outlined;
    }
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (RegExp(r'\.docx?$').hasMatch(n)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(dynamic bytes) {
    final n = bytes is num ? bytes.toInt() : int.tryParse('$bytes') ?? 0;
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
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
