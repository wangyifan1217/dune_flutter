import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../chat/native_audio_recorder.dart';

/// 会议录音上传前将 WAV 压缩为 m4a（兼容旧录音；新录音已边录边编码为 m4a）。
abstract final class MeetingAudioConverter {
  static const MethodChannel _channel = MethodChannel('dunes/meeting_audio');

  /// 若已是 m4a/mp3 则原样返回；WAV 在支持的平台上转为 m4a。
  /// [outputPath] 指定时直接写入目标路径，避免二次复制。
  static Future<String> prepareForUpload(
    String sourcePath, {
    String? outputPath,
  }) async {
    final src = sourcePath.trim();
    if (src.isEmpty) return src;

    final ext = _extension(src);
    if (ext == 'm4a' || ext == 'mp3') return src;
    if (ext != 'wav') return src;

    if (kIsWeb || !NativeAudioRecorder.isSupported) return src;

    final srcFile = File(src);
    if (!await srcFile.exists()) return src;

    final tempDir = await getTemporaryDirectory();
    final outPath = (outputPath?.trim().isNotEmpty == true)
        ? outputPath!.trim()
        : '${tempDir.path}/meeting_upload_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      final converted = await _channel.invokeMethod<String>('convertWavToM4a', {
        'inputPath': src,
        'outputPath': outPath,
      });
      final result = (converted ?? outPath).trim();
      if (result.isEmpty) return src;
      final outFile = File(result);
      if (!await outFile.exists() || await outFile.length() <= 0) return src;
      debugPrint(
        'MeetingAudioConverter wav->m4a '
        '${await srcFile.length()} -> ${await outFile.length()} bytes',
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint('MeetingAudioConverter failed: ${e.code} ${e.message}');
      return src;
    } catch (e) {
      debugPrint('MeetingAudioConverter failed: $e');
      return src;
    }
  }

  static String _extension(String path) {
    final normalized = path.replaceAll('\\', '/');
    final dot = normalized.lastIndexOf('.');
    if (dot < 0) return '';
    return normalized.substring(dot + 1).toLowerCase();
  }
}
