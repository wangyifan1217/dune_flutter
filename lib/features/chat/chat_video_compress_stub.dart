import 'dart:typed_data';

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

Future<Uint8List?> chatVideoThumbnail(String path) async => null;

Future<ChatVideoCompressResult?> chatVideoCompress(String path) async => null;

Future<ChatVideoCompressResult?> chatVideoMediaInfo(String path) async => null;
