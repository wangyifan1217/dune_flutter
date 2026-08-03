import 'package:flutter/material.dart';

import '../platform/desktop_features.dart';

/// 宽屏聊天布局断点（会话列表 + 聊天窗口双栏）。
///
/// 低于该宽度时保持移动端单栏栈导航，避免影响手机与窄窗。
const double kWideChatLayoutBreakpoint = 900;

/// 桌面端窗口默认 / 最小尺寸。
///
/// 最小宽度须明显高于 [kWideChatLayoutBreakpoint]，并预留给侧栏与会话列表，
/// 避免用户拖到过窄时落到 APP 单栏布局。
const Size kDesktopWindowDefaultSize = Size(1080, 720);
const Size kDesktopWindowMinSize = Size(1024, 680);

/// 是否使用双栏聊天布局。
///
/// 桌面端始终双栏（窗口最小尺寸由 window_manager 限制）；
/// 其余平台仍按宽度断点，避免影响手机。
bool isWideChatLayout(BuildContext context) {
  if (isDesktopCommOnly) return true;
  return MediaQuery.sizeOf(context).width >= kWideChatLayoutBreakpoint;
}
