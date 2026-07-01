import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

Future<String?> saveBytesAsFile(Uint8List bytes, String fileName) async {
  final path = await saveBytesAsFileImpl(bytes, fileName);
  return path;
}

Future<String?> openUrlAsFile(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
}) async {
  final path = await openUrlAsFileImpl(
    url,
    fileName,
    onProgress: onProgress,
  );
  return path;
}
