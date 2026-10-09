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
import '../chat/chat_file_upload_source.dart';
import '../shell/dunes_toast.dart';

const _maxDropFiles = 20;
const _maxImageBytes = 30 * 1024 * 1024;

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
      widget.enabled && isDesktopCommOnly && desktopDropLive(context);

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
      _toast(friendlyErrorText(e, fallback: '添加失败，请稍后重试'), error: true);
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
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _hovering && _dropEnabled ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color:
                        (widget.acceptsFiles
                                ? DunesColors.resolve(
                                    context,
                                    DunesColors.brandPurple,
                                    role: DunesColorRole.surface,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    DunesColors.coral,
                                    role: DunesColorRole.surface,
                                  ))
                            .withValues(alpha: 0.12),
                    border: Border.all(
                      color: widget.acceptsFiles
                          ? DunesColors.resolve(
                              context,
                              DunesColors.brandPurple,
                              role: DunesColorRole.border,
                            )
                          : DunesColors.resolve(
                              context,
                              DunesColors.coral,
                              role: DunesColorRole.border,
                            ),
                      width: 1.5,
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
    if (!_isChatImageFileName(fileName)) {
      final source = await ChatFileUploadSource.fromFile(file);
      if (source.length == 0) {
        toast('$fileName 无法读取', error: true);
        continue;
      }
      out.add(
        DesktopComposerPendingFile(
          bytes: Uint8List(0),
          uploadSource: source,
          fileName: fileName,
          mimeType: lookupMimeType(fileName) ?? 'application/octet-stream',
          isImage: false,
        ),
      );
      continue;
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      toast('$fileName 无法读取', error: true);
      continue;
    }
    final isImage = _isChatImageFileName(fileName);
    final limitMb = (_maxImageBytes / (1024 * 1024)).round();
    if (bytes.length > _maxImageBytes) {
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
