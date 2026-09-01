import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 选择会议录音并立刻落到应用目录。
/// Android 不用 file_selector：它会把整文件读进内存，大录音会 OOM 闪退。
abstract final class MeetingAudioFilePicker {
  static const MethodChannel _channel = MethodChannel('dunes/meeting_audio');

  static const supportedExtensions = {'wav', 'mp3', 'm4a', 'aac', 'amr'};

  static bool isSupportedAudioName(String name) {
    final normalized = name.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final fileName = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0) return false;
    return supportedExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  static Future<String?> pick() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final path = await _channel.invokeMethod<String>('pickAudioFile');
        final trimmed = path?.trim() ?? '';
        if (trimmed.isNotEmpty) return trimmed;
        return null;
      } on MissingPluginException {
        // 桌面调试或未实现时走选择器。
      }
    }
    return _pickViaFileSelector();
  }

  static Future<String?> _pickViaFileSelector() async {
    XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'audio',
            extensions: ['wav', 'mp3', 'm4a', 'aac', 'amr'],
            mimeTypes: [
              'audio/wav',
              'audio/x-wav',
              'audio/mpeg',
              'audio/mp4',
              'audio/m4a',
              'audio/aac',
              'audio/amr',
            ],
            uniformTypeIdentifiers: [
              'public.audio',
              'com.microsoft.waveform-audio',
              'public.mp3',
              'public.mpeg-4-audio',
              'com.apple.m4a-audio',
            ],
          ),
        ],
      );
    } catch (_) {
      try {
        file = await openFile();
      } catch (_) {
        file = null;
      }
    }
    if (file == null) return null;
    return persistPickedAudio(file);
  }

  static Future<String> persistPickedAudio(XFile file) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/meeting_uploads');
    await dir.create(recursive: true);
    final rawName = file.name.trim();
    final ext = _extensionOf(rawName.isNotEmpty ? rawName : file.path);
    final destPath =
        '${dir.path}/meeting_pick_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = File(destPath);
    final sink = dest.openWrite();
    try {
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (!await dest.exists() || await dest.length() <= 0) {
      throw Exception('录音文件保存失败');
    }
    return destPath;
  }

  static String _extensionOf(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '.m4a';
    return name.substring(dot).toLowerCase();
  }
}
