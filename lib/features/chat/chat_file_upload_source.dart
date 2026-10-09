import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

const chatMaxFileBytes = 100 * 1024 * 1024;
const chatAppMaxFileBytes = 500 * 1024 * 1024;

/// Web stays at 100MB and Android/iOS at 500MB. Desktop has no client cap.
/// Returns null when the current platform does not reject by size.
int? get chatCurrentFileLimitBytes {
  if (kIsWeb) return chatMaxFileBytes;
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    return chatAppMaxFileBytes;
  }
  return null;
}

/// A replayable file source. Each retry validates the size and opens a new stream.
/// Keep XFile itself (including Web blobs), rather than reconstructing its path.
class ChatFileUploadSource {
  ChatFileUploadSource.bytes(Uint8List bytes)
    : length = bytes.length,
      _bytes = bytes,
      _file = null,
      _modified = null;

  ChatFileUploadSource._file(XFile file, this.length, this._modified)
    : _file = file,
      _bytes = null;

  static Future<ChatFileUploadSource> fromFile(XFile file) async {
    final length = await file.length();
    // macOS drag/picker security scopes may expire before staged files send.
    // Keep modest files in memory until durable scoped access exists. Larger
    // desktop files stay on the file stream and are not size-rejected.
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        length <= chatMaxFileBytes) {
      return ChatFileUploadSource.bytes(await file.readAsBytes());
    }
    return ChatFileUploadSource._file(file, length, await file.lastModified());
  }

  final int length;
  final Uint8List? _bytes;
  final XFile? _file;
  final DateTime? _modified;

  Stream<List<int>> openRead() async* {
    final file = _file;
    if (file != null) {
      if (await file.length() != length ||
          await file.lastModified() != _modified) {
        throw const ChatFileChangedException();
      }
      var received = 0;
      await for (final chunk in file.openRead()) {
        received += chunk.length;
        if (received > length) throw const ChatFileChangedException();
        yield chunk;
      }
      if (received != length ||
          await file.length() != length ||
          await file.lastModified() != _modified) {
        throw const ChatFileChangedException();
      }
    } else {
      final bytes = _bytes!;
      for (var offset = 0; offset < length; offset += 64 * 1024) {
        final end = (offset + 64 * 1024).clamp(0, length);
        yield Uint8List.sublistView(bytes, offset, end);
      }
    }
  }
}

class ChatFileChangedException implements Exception {
  const ChatFileChangedException();

  @override
  String toString() => '文件已发生变化，请重新选择后发送';
}
