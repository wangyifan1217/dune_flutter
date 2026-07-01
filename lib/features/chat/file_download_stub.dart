import 'dart:typed_data';

Future<String?> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  throw UnsupportedError('当前平台不支持下载');
}

Future<String?> openUrlAsFileImpl(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError('当前平台不支持下载');
}
