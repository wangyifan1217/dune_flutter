import 'package:flutter/material.dart';

/// 宽屏聊天布局断点（会话列表 + 聊天窗口双栏）。
///
/// 低于该宽度时保持移动端单栏栈导航，避免影响手机与窄窗。
const double kWideChatLayoutBreakpoint = 900;

/// 是否使用双栏聊天布局（宽度驱动，与具体平台解耦）。
bool isWideChatLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= kWideChatLayoutBreakpoint;
}
