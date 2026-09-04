import 'package:flutter/foundation.dart';

/// 桌面端（Windows / macOS）：与手机 APP 分 channel；侧栏含通讯 / NOVA / 灯塔 / 我的。
bool get isDesktopCommOnly =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// 兼容旧命名。
bool get isWindowsDesktopCommOnly => isDesktopCommOnly;

/// 桌面端允许进入的屏。
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
    'CR',
    'C9',
    'C10',
    'C11',
    'C12',
    'C13',
    'CF',
    'Z2',
    'AS1',
    'AS2',
    'AS3',
    'AA1',
    'AA2',
    'AA3',
    'TA1',
    'DA1',
    'XA1',
    'WS1',
    'RA1',
    'AN1',
    // 我的及审批 / 知识库 / 企业微盘
    'B2',
    'B2P',
    'B2PERF',
    'B1',
    'B3',
    'B10',
    'B13',
    'B14',
    'P1',
    'XFP',
    'XFU',
    'XF',
    'XFS',
    'K1',
    'K2',
    'K3',
    'FD1',
    'WX',
    // 会议纪要（桌面端可上传 MM0，不含现场录音）
    'MM-L',
    'MM0',
    'MM',
    // 千机 / 灯塔
    'QJ',
    'QJC',
    'QJCD',
    'QJD',
    'QJI',
    'QJA',
    'CT1',
    'XR1',
    'AM1',
    'QJT',
    'QJP',
    'QJM',
    'QJMT',
    'QJTD',
    'QJMM',
    'QJMD',
    'QJMA',
    'QJTO',
    'QJAM',
    'QJSS',
    'QJKB',
    'QJFS',
    'QJFSD',
    'QJTR',
    'QJCF',
    'QJR',
    'QJRA',
    'QJRC',
    'LH',
    'LM',
  }.contains(screenId);
}

/// 兼容旧命名。
bool isWindowsAllowedCommScreen(String screenId) =>
    isDesktopAllowedCommScreen(screenId);
