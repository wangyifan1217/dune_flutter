import 'dart:typed_data';

Future<void> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  throw UnsupportedError('当前平台不支持下载');
}

Future<void> openUrlAsFileImpl(String url, String fileName) async {
  throw UnsupportedError('当前平台不支持下载');
}
