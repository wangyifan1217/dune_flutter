import 'package:flutter/foundation.dart';

/// Windows 桌面端（与手机 APP 分 channel，仅开放部分板块）。
bool get isWindowsDesktopCommOnly =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Windows 桌面允许进入的屏：通讯 + 我的（不含灯塔 / 会议纪要）。
bool isWindowsAllowedCommScreen(String screenId) {
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
    'K1',
    'K2',
    'K3',
  }.contains(screenId);
}
