import 'package:flutter/widgets.dart';

/// Web / 非 IO 平台：不支持拖出到本地，原样展示子组件。
class ChatDesktopFileDrag extends StatelessWidget {
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
  Widget build(BuildContext context) => child;
}
