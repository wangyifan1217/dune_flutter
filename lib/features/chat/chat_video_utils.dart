import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';

import 'chat_video_compress_stub.dart'
    if (dart.library.io) 'chat_video_compress_io.dart' as compress;
import 'chat_video_temp_stub.dart'
    if (dart.library.io) 'chat_video_temp_io.dart' as temp;

/// 微信式小视频：录制上限 60 秒。
const Duration kChatVideoRecordMaxDuration = Duration(seconds: 60);

/// 发送前体积上限（压缩后仍超限则拒绝）。
const int kChatVideoMaxBytes = 80 * 1024 * 1024;

class ChatVideoPrepared {
  const ChatVideoPrepared({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.durationSec,
    this.thumbnailBytes,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final int durationSec;
  final Uint8List? thumbnailBytes;
  final int? width;
  final int? height;
}

bool isChatVideoFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.3gp');
}

bool isChatVideoMime(String? mime) {
  final m = (mime ?? '').toLowerCase();
  return m.startsWith('video/');
}

/// 从本地路径准备可发送视频：移动端压缩，其它平台直接读入并校验大小。
Future<ChatVideoPrepared> prepareChatVideoForSend({
  required String path,
  String? preferredName,
  void Function(double progress)? onProgress,
}) async {
  onProgress?.call(0.05);
  final rawName = (preferredName ?? path.replaceAll('\\', '/').split('/').last)
      .trim();
  final baseName = rawName.isEmpty
      ? 'video-${DateTime.now().millisecondsSinceEpoch}.mp4'
      : rawName;

  var outPath = path;
  var fileName = baseName;
  var mimeType = lookupMimeType(baseName) ?? 'video/mp4';
  var durationSec = 0;
  int? width;
  int? height;

  final thumb = await compress.chatVideoThumbnail(path);
  onProgress?.call(0.15);

  final compressed = await compress.chatVideoCompress(path);
  if (compressed?.path != null && compressed!.path!.isNotEmpty) {
    outPath = compressed.path!;
    durationSec = (compressed.durationMs / 1000).round().clamp(0, 3600);
    width = compressed.width;
    height = compressed.height;
    if (!fileName.toLowerCase().endsWith('.mp4')) {
      fileName = '${fileName.replaceAll(RegExp(r'\.[^.]+$'), '')}.mp4';
    }
    mimeType = 'video/mp4';
  } else {
    final info = await compress.chatVideoMediaInfo(path);
    if (info != null) {
      durationSec = (info.durationMs / 1000).round().clamp(0, 3600);
      width = info.width;
      height = info.height;
    }
  }

  onProgress?.call(0.55);
  final bytes = await XFile(outPath).readAsBytes();
  onProgress?.call(0.85);
  if (bytes.isEmpty) {
    throw Exception('视频文件为空');
  }
  if (bytes.length > kChatVideoMaxBytes) {
    throw Exception(
      '视频过大（${(bytes.length / (1024 * 1024)).toStringAsFixed(1)}MB），请压缩到 80MB 以内',
    );
  }
  onProgress?.call(1);
  return ChatVideoPrepared(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
    durationSec: durationSec,
    thumbnailBytes: thumb,
    width: width,
    height: height,
  );
}

/// Web / 无本地路径：直接用字节发送（不做重编码压缩）。
Future<ChatVideoPrepared> prepareChatVideoBytesForSend({
  required Uint8List bytes,
  required String fileName,
  int durationSec = 0,
  Uint8List? thumbnailBytes,
}) async {
  if (bytes.isEmpty) throw Exception('视频文件为空');
  if (bytes.length > kChatVideoMaxBytes) {
    throw Exception(
      '视频过大（${(bytes.length / (1024 * 1024)).toStringAsFixed(1)}MB），请压缩到 80MB 以内',
    );
  }
  final name = fileName.trim().isEmpty
      ? 'video-${DateTime.now().millisecondsSinceEpoch}.mp4'
      : fileName.trim();
  return ChatVideoPrepared(
    bytes: bytes,
    fileName: name,
    mimeType: lookupMimeType(name) ?? 'video/mp4',
    durationSec: durationSec.clamp(0, 3600),
    thumbnailBytes: thumbnailBytes,
  );
}

/// 将鉴权下载的视频字节落到临时文件，供 video_player 播放。
Future<String> writeChatVideoTempFile(
  Uint8List bytes, {
  String fileName = 'play.mp4',
}) {
  return temp.writeChatVideoTempFileImpl(bytes, fileName: fileName);
}
