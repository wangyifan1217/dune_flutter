import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'chat_video_utils.dart';

Future<VideoPlayerController> createChatVideoFileController(
  String path,
) async {
  return VideoPlayerController.file(File(path));
}

Future<String> materializeChatVideoFile(
  Uint8List bytes, {
  required String fileName,
}) {
  return writeChatVideoTempFile(bytes, fileName: fileName);
}
