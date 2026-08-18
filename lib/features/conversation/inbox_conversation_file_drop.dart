import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../chat/chat_image_editor.dart';
import '../chat/chat_image_utils.dart';
import '../chat/desktop_composer_pending.dart';
import '../shell/dunes_toast.dart';

const _maxDropFiles = 20;
const _maxImageBytes = 30 * 1024 * 1024;
const _maxFileBytes = 100 * 1024 * 1024;

var _inboxFileDropBusy = false;

bool _isChatImageFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif');
}

String _fileNameOf(DropItem item) {
  final name = item.name.trim();
  if (name.isNotEmpty) return name;
  final path = item.path.replaceAll('\\', '/');
  final base = path.contains('/') ? path.split('/').last : path;
  return base.isEmpty ? '文件' : base;
}

/// 会话列表行：把拖入的文件放到目标会话输入框，不立即发送。
class InboxConversationFileDropTarget extends StatefulWidget {
  const InboxConversationFileDropTarget({
    super.key,
    required this.targetTitle,
    required this.resolveConversationId,
    required this.child,
    this.enabled = true,
    this.acceptsFiles = true,
    this.peerUserId,
    this.onActivateTarget,
  });

  final String targetTitle;
  final Future<int?> Function() resolveConversationId;
  final Widget child;
  final bool enabled;
  final bool acceptsFiles;
  final int? peerUserId;
  final VoidCallback? onActivateTarget;

  @override
  State<InboxConversationFileDropTarget> createState() =>
      _InboxConversationFileDropTargetState();
}

class _InboxConversationFileDropTargetState
    extends State<InboxConversationFileDropTarget> {
  var _hovering = false;

  bool get _dropEnabled =>
      widget.enabled &&
      isDesktopCommOnly &&
      TickerMode.valuesOf(context).enabled;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: error ? DunesToastKind.error : DunesToastKind.normal,
    );
  }

  Future<void> _onDropped(DropDoneDetails detail) async {
    if (!mounted || !_dropEnabled) return;
    final title = widget.targetTitle.trim().isEmpty
        ? '该会话'
        : widget.targetTitle.trim();
    if (!widget.acceptsFiles) {
      _toast('无法发送到$title', error: true);
      return;
    }
    if (_inboxFileDropBusy) {
      _toast('正在处理，请稍后再拖入');
      return;
    }

    final accessed = <Uint8List>[];
    final files = <DropItem>[];
    try {
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(item);
      }
      if (files.isEmpty) {
        _toast('请拖入文件（不支持文件夹）');
        return;
      }
      if (files.length > _maxDropFiles) {
        _toast('一次最多拖入 $_maxDropFiles 个文件');
      }
      _inboxFileDropBusy = true;
      final pending = await _readDroppedFiles(
        files.take(_maxDropFiles).toList(),
        toast: _toast,
      );
      if (pending.isEmpty) return;
      final conversationId = await widget.resolveConversationId();
      if ((conversationId ?? 0) <= 0 && (widget.peerUserId ?? 0) <= 0) {
        throw Exception('无法打开会话');
      }
      DesktopComposerPending.offer(
        conversationId: conversationId,
        peerUserId: widget.peerUserId,
        files: pending,
      );
      widget.onActivateTarget?.call();
    } catch (e) {
      _toast(
        friendlyErrorText(e, fallback: '添加失败，请稍后重试'),
        error: true,
      );
    } finally {
      _inboxFileDropBusy = false;
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: _dropEnabled,
      onDragEntered: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onDragExited: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      onDragDone: (detail) {
        if (_hovering) setState(() => _hovering = false);
        unawaited(_onDropped(detail));
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (widget.acceptsFiles
                            ? DunesColors.accent
                            : DunesColors.coral)
                        .withValues(alpha: 0.12),
                    border: Border(
                      left: BorderSide(
                        color: widget.acceptsFiles
                            ? DunesColors.accent
                            : DunesColors.coral,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<List<DesktopComposerPendingFile>> _readDroppedFiles(
  List<DropItem> files, {
  required void Function(String message, {bool error}) toast,
}) async {
  final out = <DesktopComposerPendingFile>[];
  for (final file in files) {
    final fileName = _fileNameOf(file);
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      toast('$fileName 无法读取', error: true);
      continue;
    }
    final isImage = _isChatImageFileName(fileName);
    final limit = isImage ? _maxImageBytes : _maxFileBytes;
    final limitMb = (limit / (1024 * 1024)).round();
    if (bytes.length > limit) {
      toast('$fileName 超过 ${limitMb}MB 上限，无法添加', error: true);
      continue;
    }
    var outBytes = bytes;
    var outName = fileName;
    if (isImage && !chatImageShouldSkipEditor(fileName: fileName)) {
      final compressed = await compressChatImageForSend(
        bytes,
        fileName: fileName,
      );
      if (compressed != null && compressed.isNotEmpty) {
        outBytes = compressed;
        outName = chatImageEditedFileName(fileName);
      }
    }
    out.add(
      DesktopComposerPendingFile(
        bytes: outBytes,
        fileName: outName,
        mimeType:
            lookupMimeType(outName) ??
            (isImage ? 'image/jpeg' : 'application/octet-stream'),
        isImage: isImage,
        sourceLabel: isImage ? '图片' : '文件',
      ),
    );
  }
  return out;
}
