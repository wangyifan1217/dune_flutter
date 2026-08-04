import 'dart:typed_data';

Future<String> writeChatVoiceTempFileImpl(
  Uint8List bytes, {
  String fileName = 'voice.m4a',
}) async {
  throw UnsupportedError('当前平台不支持本地临时语音文件');
}
