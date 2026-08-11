import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../shell/dunes_toast.dart';
import 'administrative_notice_service.dart';

const _accent = Color(0xFF3D7A8C);
const _maxFiles = 10;
const _maxBytes = 30 * 1024 * 1024;
const _exts = <String>[
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'txt',
  'zip',
  'rar',
];

class AdministrativeNoticeAttachmentField extends StatefulWidget {
  const AdministrativeNoticeAttachmentField({
    super.key,
    required this.service,
    required this.attachments,
    required this.onChanged,
    this.enabled = true,
  });

  final AdministrativeNoticeService service;
  final List<Map<String, dynamic>> attachments;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;

  @override
  State<AdministrativeNoticeAttachmentField> createState() =>
      _AdministrativeNoticeAttachmentFieldState();
}

class _AdministrativeNoticeAttachmentFieldState
    extends State<AdministrativeNoticeAttachmentField> {
  bool _uploading = false;
  bool _dragging = false;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  void _toast(String msg, {DunesToastKind kind = DunesToastKind.normal}) {
    if (!mounted) return;
    showDunesToast(context, msg, kind: kind);
  }

  bool _allowed(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _exts.contains(name.substring(dot + 1).toLowerCase());
  }

  Future<void> _pick() async {
    if (!widget.enabled || _uploading) return;
    final room = _maxFiles - widget.attachments.length;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个附件', kind: DunesToastKind.error);
      return;
    }
    setState(() => _uploading = true);
    try {
      final group = XTypeGroup(label: 'files', extensions: _exts);
      final picked = await openFiles(acceptedTypeGroups: [group]);
      if (picked.isEmpty) return;
      await _ingest(picked, room: room);
    } catch (e) {
      _toast('选择文件失败：$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (!widget.enabled || _uploading) return;
    final room = _maxFiles - widget.attachments.length;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个附件', kind: DunesToastKind.error);
      return;
    }
    setState(() {
      _uploading = true;
      _dragging = false;
    });
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        _toast('请拖入文件（不支持文件夹）', kind: DunesToastKind.error);
        return;
      }
      await _ingest(files, room: room);
    } catch (e) {
      _toast('拖拽上传失败：$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _ingest(List<XFile> picked, {required int room}) async {
    final next = List<Map<String, dynamic>>.from(widget.attachments);
    var accepted = 0;
    for (final file in picked) {
      if (accepted >= room) {
        _toast('最多上传 $_maxFiles 个附件', kind: DunesToastKind.error);
        break;
      }
      final name = file.name.isEmpty ? 'attachment' : file.name;
      if (!_allowed(name)) {
        _toast('$name 类型不支持', kind: DunesToastKind.error);
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBytes) {
        _toast('$name 超过 30MB 限制', kind: DunesToastKind.error);
        continue;
      }
      try {
        next.add(await widget.service.upload(file));
        accepted++;
        widget.onChanged(List<Map<String, dynamic>>.from(next));
        if (mounted) setState(() {});
      } catch (e) {
        _toast('$name 上传失败：$e', kind: DunesToastKind.error);
      }
    }
    if (accepted > 0) _toast('已上传 $accepted 个附件');
  }

  void _remove(int index) {
    final next = List<Map<String, dynamic>>.from(widget.attachments)
      ..removeAt(index);
    widget.onChanged(next);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final zone = Material(
      color: _dragging ? _accent.withValues(alpha: 0.08) : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: (!widget.enabled || _uploading) ? null : _pick,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _dragging
                  ? _accent.withValues(alpha: 0.45)
                  : const Color(0xFFE8EAED),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: _dragging ? _accent : DunesColors.text3,
              ),
              const SizedBox(height: 6),
              Text(
                _supportsDesktopDrop || isDesktopCommOnly
                    ? (_uploading ? '上传中…' : '点击选择，或拖拽文件/图片到此处（可多选）')
                    : (_uploading ? '上传中…' : '点击选择图片或文件（可多选）'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _dragging ? _accent : DunesColors.text2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '支持 pdf / office / 图片等，单文件 ≤ 30MB，最多 10 个',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_supportsDesktopDrop)
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (d) => unawaited(_onDrop(d)),
            child: zone,
          )
        else
          zone,
        if (widget.attachments.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < widget.attachments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8EAED)),
                ),
                child: Row(
                  children: [
                    Icon(
                      ((widget.attachments[i]['mimeType'] ?? '')
                              .toString()
                              .startsWith('image/'))
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 18,
                      color: _accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (widget.attachments[i]['fileName'] ?? '附件')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          Text(
                            _formatSize(
                              (widget.attachments[i]['sizeBytes'] as num?)
                                      ?.toInt() ??
                                  0,
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.enabled ? () => _remove(i) : null,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
