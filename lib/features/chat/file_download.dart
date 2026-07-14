import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

Future<String?> saveBytesAsFile(Uint8List bytes, String fileName) async {
  final path = await saveBytesAsFileImpl(bytes, fileName);
  return path;
}

/// 按 [cacheKey]（通常为 objectKey）落盘，二次点击可直接打开。
Future<String?> saveBytesAsCachedFile(
  Uint8List bytes,
  String cacheKey,
  String fileName,
) async {
  final path = await saveBytesAsCachedFileImpl(bytes, cacheKey, fileName);
  return path;
}

Future<String?> findCachedChatFile(String cacheKey, String fileName) async {
  return findCachedChatFileImpl(cacheKey, fileName);
}

Future<String?> openUrlAsFile(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
  String? cacheKey,
}) async {
  final path = await openUrlAsFileImpl(
    url,
    fileName,
    onProgress: onProgress,
    cacheKey: cacheKey,
  );
  return path;
}

/// 用系统默认应用打开本地文件。
Future<void> openLocalFile(String path) async {
  await openLocalFileImpl(path);
}

/// 在资源管理器 / Finder 中显示文件。
Future<void> revealLocalFile(String path) async {
  await revealLocalFileImpl(path);
}
