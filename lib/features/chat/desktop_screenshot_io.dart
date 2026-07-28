import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/windows_desktop_tray.dart';
import 'desktop_screenshot_windows.dart' as win;

Future<Uint8List?> captureDesktopRegionScreenshotImpl() async {
  if (Platform.isWindows) {
    // 新方案：系统截图，不藏本窗口。
    return win.captureWindowsRegionScreenshot();
  }
  if (Platform.isMacOS) {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}dunes_shot_${DateTime.now().millisecondsSinceEpoch}.png';
    // macOS 用系统交互截图；短暂透明避免截到自己，截完必恢复。
    var dimmed = false;
    try {
      try {
        await windowManager.setOpacity(0.02);
        dimmed = true;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } catch (_) {}
      final result = await Process.run('screencapture', <String>[
        '-i',
        '-x',
        path,
      ]);
      if (result.exitCode != 0) return null;
      final file = File(path);
      if (!await file.exists()) return Pasteboard.image;
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      if (bytes.isEmpty) return null;
      return bytes;
    } finally {
      if (dimmed) {
        try {
          await windowManager.setOpacity(1);
          await windowManager.show();
          await windowManager.focus();
          windowsTrayReveal();
        } catch (_) {}
      }
    }
  }
  throw UnsupportedError('当前平台不支持截图');
}

Future<void> registerDesktopScreenshotHotkeyImpl(VoidCallback onPressed) async {
  if (!Platform.isWindows) return;
  await win.WindowsScreenshotHotkey.ensureRegistered(onPressed);
}

void clearDesktopScreenshotHotkeyImpl(VoidCallback onPressed) {
  if (!Platform.isWindows) return;
  win.WindowsScreenshotHotkey.clear(onPressed);
}
