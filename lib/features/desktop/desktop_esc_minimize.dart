import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import 'windows_desktop_tray.dart';

/// 根 Navigator，用来判断 Esc 时是否已有弹窗/预览可关闭。
final GlobalKey<NavigatorState> dunesAppNavigatorKey =
    GlobalKey<NavigatorState>();

/// PC：Esc 最小化到任务栏。弹窗 / 预览 / 输入法组字中不拦截，避免抢现有关闭行为。
class DesktopEscMinimize extends StatefulWidget {
  const DesktopEscMinimize({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopEscMinimize> createState() => _DesktopEscMinimizeState();
}

class _DesktopEscMinimizeState extends State<DesktopEscMinimize> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!isDesktopCommOnly) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (_isImeComposing()) return false;
    if (_hasPoppableRoute()) return false;
    unawaited(windowsTrayMinimize());
    return true;
  }

  bool _isImeComposing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    final editable = ctx.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return false;
    final composing = editable.textEditingValue.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  bool _hasPoppableRoute() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null) {
      final focusedNav = Navigator.maybeOf(ctx);
      if (focusedNav != null && focusedNav.canPop()) return true;
    }
    final root = dunesAppNavigatorKey.currentState;
    return root != null && root.canPop();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
