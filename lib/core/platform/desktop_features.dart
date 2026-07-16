import 'package:flutter/foundation.dart';

/// 桌面端（Windows / macOS）：与手机 APP 分 channel，仅开放通讯 + 我的。
bool get isDesktopCommOnly =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// 兼容旧命名。
bool get isWindowsDesktopCommOnly => isDesktopCommOnly;

/// 桌面端允许进入的屏：通讯 + 我的（不含灯塔 / 会议纪要）。
bool isDesktopAllowedCommScreen(String screenId) {
  return const <String>{
    // 通讯
    'C1',
    'C2',
    'C3',
    'C4',
    'C5',
    'C6',
    'C7',
    'C9',
    'C10',
    'C11',
    'C12',
    'C13',
    'Z2',
    // 我的及审批 / 知识库
    'B2',
    'B1',
    'B3',
    'B10',
    'B14',
    'P1',
    'XFP',
    'XFU',
    'XF',
    'XFS',
    'K1',
    'K2',
    'K3',
    'WX',
  }.contains(screenId);
}

/// 兼容旧命名。
bool isWindowsAllowedCommScreen(String screenId) =>
    isDesktopAllowedCommScreen(screenId);
