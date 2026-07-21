import 'dart:typed_data';

import 'package:just_screenshot/screenshot.dart';

/// Windows：插件自带交互式框选层（类似微信，非 ms-screenclip）。
Future<Uint8List?> captureWindowsRegionScreenshot() async {
  final data = await Screenshot.instance.capture(
    mode: ScreenshotMode.region,
    includeCursor: false,
  );
  if (data == null) return null;
  if (data.bytes.isEmpty) return null;
  return data.bytes;
}
