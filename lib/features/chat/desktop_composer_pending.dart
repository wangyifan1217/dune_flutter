import 'dart:typed_data';

import 'desktop_composer_focus.dart';

class DesktopComposerPendingFile {
  const DesktopComposerPendingFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.isImage,
    this.sourceLabel = '文件',
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final bool isImage;
  final String sourceLabel;
}

/// 从会话列表拖入的附件：先挂到目标会话输入框，由用户确认后再发送。
class DesktopComposerPending {
  DesktopComposerPending._();

  static int? _conversationId;
  static int? _peerUserId;
  static List<DesktopComposerPendingFile> _files =
      const <DesktopComposerPendingFile>[];

  static void offer({
    int? conversationId,
    int? peerUserId,
    required List<DesktopComposerPendingFile> files,
  }) {
    if (files.isEmpty) return;
    _conversationId = (conversationId ?? 0) > 0 ? conversationId : null;
    _peerUserId = (peerUserId ?? 0) > 0 ? peerUserId : null;
    _files = List<DesktopComposerPendingFile>.of(files);
    DesktopComposerFocus.request();
  }

  static List<DesktopComposerPendingFile>? take({
    int conversationId = 0,
    int peerUserId = 0,
  }) {
    if (_files.isEmpty) return null;
    final idMatch = conversationId > 0 && conversationId == _conversationId;
    final peerMatch = peerUserId > 0 && peerUserId == _peerUserId;
    if (!idMatch && !peerMatch) return null;
    final out = _files;
    _conversationId = null;
    _peerUserId = null;
    _files = const <DesktopComposerPendingFile>[];
    return out;
  }
}
