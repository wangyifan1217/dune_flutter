import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

/// 过滤出当前能读的本地文件（排除目录、网页 URL、已删除路径）。
List<String> existingLocalFilePaths(List<String> paths) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in paths) {
    final path = raw.trim();
    if (path.isEmpty || seen.contains(path)) continue;
    seen.add(path);
    try {
      if (FileSystemEntity.typeSync(path, followLinks: true) ==
          FileSystemEntityType.file) {
        out.add(path);
      }
    } catch (_) {}
  }
  return out;
}

Future<Uint8List> readLocalFileBytes(String filePath) async {
  if (kIsWeb) return Uint8List(0);
  final path = filePath.trim();
  if (path.isEmpty) return Uint8List(0);
  final file = File(path);
  if (!await file.exists()) return Uint8List(0);
  return file.readAsBytes();
}

/// Windows / macOS：把本地文件路径写入系统剪贴板，供资源管理器或其他应用粘贴。
Future<void> writeLocalPathToClipboard(String filePath) async {
  if (kIsWeb) return;
  final path = filePath.trim();
  if (path.isEmpty) return;
  final file = File(path);
  if (!await file.exists()) return;

  try {
    final ok = await Pasteboard.writeFiles([path]);
    if (ok) return;
  } catch (e) {
    debugPrint('[ChatFileClipboard] Pasteboard.writeFiles failed: $e');
  }

  if (!Platform.isWindows) return;
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
      '[ChatFileClipboard] Set-Clipboard failed: ${result.stderr}',
    );
  }
}

/// 把字节写成临时文件后写入系统剪贴板；返回临时路径（失败返回 null）。
Future<String?> writeBytesFileToClipboard(
  Uint8List bytes, {
  required String fileName,
}) async {
  if (kIsWeb || bytes.isEmpty) return null;
  final dir = await getTemporaryDirectory();
  final safeName = fileName.trim().isEmpty ? 'file.bin' : fileName.trim();
  final path =
      '${dir.path}${Platform.pathSeparator}dunes-chat-copy-file-${DateTime.now().millisecondsSinceEpoch}-$safeName';
  await File(path).writeAsBytes(bytes, flush: true);
  await writeLocalPathToClipboard(path);
  return path;
}
