import 'dart:typed_data';

import 'package:video_player/video_player.dart';

Future<VideoPlayerController> createChatVideoFileController(
  String path,
) async {
  throw UnsupportedError('当前平台不支持本地视频文件播放');
}

Future<String> materializeChatVideoFile(
  Uint8List bytes, {
  required String fileName,
}) async {
  throw UnsupportedError('当前平台不支持本地临时视频文件');
}
