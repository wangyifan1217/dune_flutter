import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Windows：把图片文件交给系统剪贴板（PowerShell Set-Clipboard）。
/// 调用方应放在后台，避免卡住「复制」反馈。
Future<void> writeImageFileToClipboard(
  Uint8List imageBytes, {
  required String fileName,
}) async {
  if (kIsWeb || !Platform.isWindows) return;
  if (imageBytes.isEmpty) return;
  final dir = await getTemporaryDirectory();
  final safeName = fileName.trim().isEmpty ? 'image.png' : fileName.trim();
  final path =
      '${dir.path}${Platform.pathSeparator}dunes-chat-copy-${DateTime.now().millisecondsSinceEpoch}-$safeName';
  await File(path).writeAsBytes(imageBytes, flush: true);
  final escaped = path.replaceAll("'", "''");
  final result = await Process.run('powershell', <String>[
    '-NoProfile',
    '-NoLogo',
    '-NonInteractive',
    '-Command',
    "Set-Clipboard -Path '$escaped'",
  ]);
  if (result.exitCode != 0) {
    debugPrint(
      '[ChatImageClipboard] Set-Clipboard failed: ${result.stderr}',
    );
  }
}

