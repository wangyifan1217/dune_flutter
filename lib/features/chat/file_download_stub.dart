import 'dart:typed_data';

Future<String?> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  throw UnsupportedError('当前平台不支持下载');
}

Future<String?> saveBytesAsCachedFileImpl(
  Uint8List bytes,
  String cacheKey,
  String fileName,
) async {
  throw UnsupportedError('当前平台不支持下载');
}

Future<String?> findCachedChatFileImpl(String cacheKey, String fileName) async {
  return null;
}

Future<String?> openUrlAsFileImpl(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
  String? cacheKey,
}) async {
  throw UnsupportedError('当前平台不支持下载');
}

Future<void> openLocalFileImpl(String path) async {
  throw UnsupportedError('当前平台不支持打开本地文件');
}

Future<void> revealLocalFileImpl(String path) async {
  throw UnsupportedError('当前平台不支持打开本地文件');
}
