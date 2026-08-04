import 'dart:typed_data';

import '../conversation/conversation_service.dart';
import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

Future<String?> saveBytesAsFile(Uint8List bytes, String fileName) async {
  final path = await saveBytesAsFileImpl(bytes, fileName);
  return path;
}

/// 按会话目录落盘：`沙丘文件/{conversationId}/{fileName}`。
///
/// [cacheKey]（通常为 objectKey）用于兼容旧版哈希子目录，以及下载进度标识。
/// 未传 [conversationId] 时仍走旧版 `沙丘文件/{hash(cacheKey)}/{fileName}`。
Future<String?> saveBytesAsCachedFile(
  Uint8List bytes,
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  final path = await saveBytesAsCachedFileImpl(
    bytes,
    cacheKey,
    fileName,
    conversationId: conversationId,
  );
  return path;
}

Future<String?> findCachedChatFile(
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  return findCachedChatFileImpl(
    cacheKey,
    fileName,
    conversationId: conversationId,
  );
}

Future<String?> openUrlAsFile(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
  String? cacheKey,
  int? conversationId,
  ChatUploadCancelToken? cancelToken,
}) async {
  final path = await openUrlAsFileImpl(
    url,
    fileName,
    onProgress: onProgress,
    cacheKey: cacheKey,
    conversationId: conversationId,
    cancelToken: cancelToken,
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

/// 当前 IM 附件实际保存根目录（含用户自选或默认「下载/沙丘文件」）。
Future<String> resolveImSaveDirPath() async {
  return resolveImSaveDirPathImpl();
}

/// 删除本地已缓存附件（用于「重新下载」）。
Future<void> deleteCachedChatFile(
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  await deleteCachedChatFileImpl(
    cacheKey,
    fileName,
    conversationId: conversationId,
  );
}

/// 微盘文件落盘：`{根目录}/企业微盘/{fileName}`（无 hash 子目录）。
Future<String?> saveBytesAsDriveFile(
  Uint8List bytes,
  String fileName, {
  String? cacheKey,
}) async {
  return saveBytesAsDriveFileImpl(bytes, fileName, cacheKey: cacheKey);
}

/// 查找已下载的微盘文件（先查「企业微盘」，再兼容旧 hash 目录）。
Future<String?> findCachedDriveFile(
  String fileName, {
  String? cacheKey,
}) async {
  return findCachedDriveFileImpl(fileName, cacheKey: cacheKey);
}
