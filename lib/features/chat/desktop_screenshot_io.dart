import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import 'desktop_screenshot_windows.dart' as win;

Future<Uint8List?> captureDesktopRegionScreenshotImpl() async {
  if (Platform.isWindows) {
    return win.captureWindowsRegionScreenshot();
  }
  if (Platform.isMacOS) {
    // macOS：先静默抓全屏，再由上层用编辑器裁剪；
    // 系统 -i 交互截图观感接近系统工具，故这里抓全屏后交给编辑。
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}dunes_shot_${DateTime.now().millisecondsSinceEpoch}.png';
    final result = await Process.run('screencapture', <String>['-x', path]);
    if (result.exitCode != 0) {
      throw Exception('截图失败');
    }
    final file = File(path);
    if (!await file.exists()) {
      // 回退剪贴板
      return Pasteboard.image;
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    if (bytes.isEmpty) return null;
    return bytes;
  }
  throw UnsupportedError('当前平台不支持截图');
}
