import 'package:flutter/widgets.dart';

class NovaPresenceDesktopHooks {
  const NovaPresenceDesktopHooks({
    required this.onSend,
    required this.onExpand,
    required this.onCollapse,
    required this.onReattach,
    this.onConfirm,
    this.onCancel,
    this.onAsk,
    this.onMoved,
    this.onOpen,
  });

  final ValueChanged<String> onSend;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onReattach;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final ValueChanged<String>? onAsk;
  final ValueChanged<Map<String, dynamic>>? onMoved;
  final VoidCallback? onOpen;
}

class NovaPresenceDesktopBridge {
  static Future<void> bind(NovaPresenceDesktopHooks hooks) async {}

  static void unbind() {}

  static Future<bool> detach({
    required Offset viewOrigin,
    required Map<String, dynamic> state,
  }) async => false;

  static Future<void> push(Map<String, dynamic> state) async {}

  static Future<void> hide() async {}
}

bool isNovaPresenceDesktopWindowArgs(List<String> args) => false;

Future<bool> isNovaPresenceDesktopEngine() async => false;

Future<void> runNovaPresenceDesktopWindow() async {}
