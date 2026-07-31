import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_models.dart';

const _themePurple = Color(0xFF7B5CD8);
const _maxFiles = 10;
const _maxBytes = 30 * 1024 * 1024;
const _exts = [
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

class TaskAttachmentField extends StatefulWidget {
  const TaskAttachmentField({
    super.key,
    required this.session,
    required this.files,
    required this.onChanged,
    this.accentColor = _themePurple,
  });

  final AuthSession session;
  final List<TaskAttachment> files;
  final ValueChanged<List<TaskAttachment>> onChanged;
  final Color accentColor;

  @override
  State<TaskAttachmentField> createState() => _TaskAttachmentFieldState();
}

class _TaskAttachmentFieldState extends State<TaskAttachmentField> {
  late final TaskApi _api = TaskApi(widget.session);
  bool _picking = false;
  bool _dragging = false;

  bool get _supportsDesktopDrop {
    if (kIsWeb) return true;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  }

  void _toast(String msg) {
    if (!mounted) return;
    showDunesCenterToast(context, msg);
  }

  Future<void> _pick() async {
    if (_picking) return;
    final room = _maxFiles - widget.files.length;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个文件');
      return;
    }
    setState(() => _picking = true);
    try {
      final group = XTypeGroup(label: 'files', extensions: _exts);
      final picked = await openFiles(acceptedTypeGroups: [group]);
      if (picked.isEmpty) return;
      await _ingest(picked, room: room);
    } catch (e) {
      _toast('选择文件失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _onDrop(DropDoneDetails detail) async {
    if (_picking) return;
    final room = _maxFiles - widget.files.length;
    if (room <= 0) {
      _toast('最多上传 $_maxFiles 个文件');
      return;
    }
    setState(() {
      _picking = true;
      _dragging = false;
    });
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        _toast('请拖入文件（不支持文件夹）');
        return;
      }
      await _ingest(files, room: room);
    } catch (e) {
      _toast('拖拽上传失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool _allowed(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return _exts.contains(ext);
  }

  Future<void> _ingest(List<XFile> picked, {required int room}) async {
    final next = List<TaskAttachment>.from(widget.files);
    var accepted = 0;
    for (final file in picked) {
      if (accepted >= room) {
        _toast('最多上传 $_maxFiles 个文件');
        break;
      }
      final name = file.name;
      if (!_allowed(name)) {
        _toast('$name 类型不支持');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBytes) {
        _toast('$name 超过 30MB 限制');
        continue;
      }
      try {
        final uploaded = await _api.uploadAttachment(bytes: bytes, fileName: name);
        next.add(uploaded);
        accepted++;
        widget.onChanged(List<TaskAttachment>.from(next));
        if (mounted) setState(() {});
      } catch (e) {
        _toast('$name 上传失败：$e');
      }
    }
    if (accepted > 0) _toast('已上传 $accepted 个文件');
  }

  void _remove(int index) {
    final next = List<TaskAttachment>.from(widget.files)..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final zone = Material(
      color: _dragging
          ? accent.withValues(alpha: 0.08)
          : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _picking ? null : _pick,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _dragging
                  ? accent.withValues(alpha: 0.45)
                  : const Color(0xFFE8EAED),
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                color: _dragging ? accent : DunesColors.text3,
              ),
              const SizedBox(height: 6),
              Text(
                _supportsDesktopDrop || isDesktopCommOnly
                    ? (_picking ? '上传中…' : '点击选择，或拖拽文件到此处（可多选）')
                    : (_picking ? '上传中…' : '点击选择文件（可多选）'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _dragging ? accent : DunesColors.text2,
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
        const Text(
          '附件',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DunesColors.text2,
          ),
        ),
        const SizedBox(height: 8),
        if (_supportsDesktopDrop)
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (d) => unawaited(_onDrop(d)),
            child: zone,
          )
        else
          zone,
        if (widget.files.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < widget.files.length; i++)
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
                    Icon(Icons.insert_drive_file_outlined, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.files[i].fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _remove(i),
                      icon: const Icon(Icons.close, size: 18, color: DunesColors.text3),
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
