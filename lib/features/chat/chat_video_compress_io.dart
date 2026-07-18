import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

class ChatVideoCompressResult {
  const ChatVideoCompressResult({
    this.path,
    this.durationMs = 0,
    this.width,
    this.height,
  });

  final String? path;
  final int durationMs;
  final int? width;
  final int? height;
}

bool get _mobile =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

Future<Uint8List?> chatVideoThumbnail(String path) async {
  if (!_mobile) return null;
  try {
    final bytes = await VideoCompress.getByteThumbnail(
      path,
      quality: 55,
      position: -1,
    );
    return bytes == null ? null : Uint8List.fromList(bytes);
  } catch (_) {
    return null;
  }
}

Future<ChatVideoCompressResult?> chatVideoCompress(String path) async {
  if (!_mobile) return chatVideoMediaInfo(path);
  try {
    final info = await VideoCompress.compressVideo(
      path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
      frameRate: 30,
    );
    if (info == null) return null;
    return ChatVideoCompressResult(
      path: info.path,
      durationMs: (info.duration ?? 0).round(),
      width: info.width,
      height: info.height,
    );
  } catch (_) {
    return null;
  }
}

Future<ChatVideoCompressResult?> chatVideoMediaInfo(String path) async {
  if (!_mobile) return null;
  try {
    final info = await VideoCompress.getMediaInfo(path);
    return ChatVideoCompressResult(
      path: info.path,
      durationMs: (info.duration ?? 0).round(),
      width: info.width,
      height: info.height,
    );
  } catch (_) {
    return null;
  }
}
