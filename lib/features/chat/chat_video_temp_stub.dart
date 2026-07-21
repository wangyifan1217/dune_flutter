import 'dart:typed_data';

Future<String> writeChatVideoTempFileImpl(
  Uint8List bytes, {
  String fileName = 'play.mp4',
}) async {
  throw UnsupportedError('当前平台不支持本地临时视频文件');
}
