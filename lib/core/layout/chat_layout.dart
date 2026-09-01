import 'package:flutter/foundation.dart';
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

/// 微信式气泡约占聊天栏宽度。仅 Android 折叠展开时拉宽；桌面/Web/iPad 仍 280。
const double kChatBubbleWidthFactor = 0.75;

/// 普通手机气泡上限（与历史实现一致）。
const double kChatBubblePhoneMaxWidth = 280;

/// 折叠内屏上图片相对整窗宽度的上限（普通手机仍用 0.32）。
const double kChatImageFoldWidthFactor = 0.45;

/// 普通手机宽度上限：低于此仍按 0.32 缩放图片，避免直板机图片变大。
const double kChatPhoneWidthCap = 430;

/// 是否把气泡随栏宽拉到约 75%。仅 Android（含折叠屏），避免改 PC / Web / iPad。
bool get shouldExpandChatBubbles {
  if (kIsWeb || isDesktopCommOnly) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// 是否使用双栏聊天布局。
///
/// 桌面端始终双栏（窗口最小尺寸由 window_manager 限制）。
/// Android（含折叠屏）始终单栏，避免展开后变成 PC 壳。
/// iOS / Web 仍按宽度断点，避免影响现有 iPad 与宽屏 Web。
bool isWideChatLayout(BuildContext context) {
  if (isDesktopCommOnly) return true;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return false;
  }
  return MediaQuery.sizeOf(context).width >= kWideChatLayoutBreakpoint;
}

/// 会话气泡最大宽度。
///
/// [available] 为消息行可用宽度。普通手机（约 75% ≤ 280）仍返回 280；
/// 折叠展开后返回 `available * 0.75`。桌面/Web/iPad 默认不拉宽。
double chatBubbleMaxWidth(double available, {bool? expand}) {
  final useExpand = expand ?? shouldExpandChatBubbles;
  if (!(available > 0) || !available.isFinite) {
    return kChatBubblePhoneMaxWidth;
  }
  if (!useExpand) {
    return available < kChatBubblePhoneMaxWidth
        ? available
        : kChatBubblePhoneMaxWidth;
  }
  final byFactor = available * kChatBubbleWidthFactor;
  if (byFactor <= kChatBubblePhoneMaxWidth) {
    return available < kChatBubblePhoneMaxWidth
        ? available
        : kChatBubblePhoneMaxWidth;
  }
  return byFactor;
}
