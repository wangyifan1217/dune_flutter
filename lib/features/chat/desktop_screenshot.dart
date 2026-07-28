import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'desktop_screenshot_stub.dart'
    if (dart.library.io) 'desktop_screenshot_io.dart' as impl;

/// 应用内区域截图（类似微信 PC，非系统自带截图工具）。
/// 取消返回 null。
Future<Uint8List?> captureDesktopRegionScreenshot() =>
    impl.captureDesktopRegionScreenshotImpl();

/// 注册桌面截图热键（Windows: Ctrl+Alt+A 全局热键）。
Future<void> registerDesktopScreenshotHotkey(VoidCallback onPressed) =>
    impl.registerDesktopScreenshotHotkeyImpl(onPressed);

void clearDesktopScreenshotHotkey(VoidCallback onPressed) =>
    impl.clearDesktopScreenshotHotkeyImpl(onPressed);
