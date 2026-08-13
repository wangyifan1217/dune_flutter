import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/platform/desktop_features.dart';

const _kChannel = MethodChannel('nova.dunes/desktop_file_drag');

/// 把会话里已落盘的文件/图片拖到资源管理器或 Finder。
///
/// 仅 Windows / macOS 生效；操作为复制，不会挪走应用内缓存。
class ChatDesktopFileDrag extends StatefulWidget {
  const ChatDesktopFileDrag({
    super.key,
    required this.fileName,
    required this.resolveLocalPath,
    required this.child,
    this.enabled = true,
  });

  final String fileName;
  final Future<String?> Function() resolveLocalPath;
  final Widget child;
  final bool enabled;

  @override
  State<ChatDesktopFileDrag> createState() => _ChatDesktopFileDragState();
}

class _ChatDesktopFileDragState extends State<ChatDesktopFileDrag> {
  var _starting = false;
  Future<String?>? _warmPath;

  void _warm() {
    _warmPath ??= widget.resolveLocalPath();
  }

  Future<void> _beginDrag() async {
    if (_starting || !widget.enabled || !isDesktopCommOnly) return;
    _starting = true;
    _warm();
    try {
      final path = ((await _warmPath)?.trim()) ?? '';
      _warmPath = null;
      if (!mounted || path.isEmpty) return;
      await _kChannel.invokeMethod<void>('start', <String, dynamic>{
        'paths': <String>[path],
        'fileName': widget.fileName,
      });
    } on MissingPluginException {
      // 旧包未带原生通道时静默忽略。
    } catch (_) {
    } finally {
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !isDesktopCommOnly) return widget.child;
    return Listener(
      onPointerDown: (_) => _warm(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) {
          unawaited(_beginDrag());
        },
        child: widget.child,
      ),
    );
  }
}
