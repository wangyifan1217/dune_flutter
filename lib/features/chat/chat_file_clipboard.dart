import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chat_file_clipboard_io.dart'
    if (dart.library.html) 'chat_file_clipboard_stub.dart' as io;
import 'chat_image_clipboard.dart';

/// 会话内「复制文件 → 粘贴发送」剪贴板（PC）。
///
/// 与 [ChatImageClipboard] 互斥：写入文件时清掉图片备份，避免粘贴抢发旧图。
class ChatFileClipboard {
  ChatFileClipboard._();

  static Uint8List? _bytes;
  static String _fileName = 'file.bin';
  static String? _localPath;
  static DateTime? _at;
  static int _writeGen = 0;

  static bool get hasFile {
    final at = _at;
    if (at == null) return false;
    if (DateTime.now().difference(at) > const Duration(hours: 2)) {
      clear();
      return false;
    }
    final bytes = _bytes;
    if (bytes != null && bytes.isNotEmpty) return true;
    final path = (_localPath ?? '').trim();
    return path.isNotEmpty;
  }

  static ({Uint8List bytes, String fileName, String? localPath})? peek() {
    if (!hasFile) return null;
    return (
      bytes: _bytes ?? Uint8List(0),
      fileName: _fileName,
      localPath: _localPath,
    );
  }

  static void clear() {
    _writeGen++;
    _bytes = null;
    _fileName = 'file.bin';
    _localPath = null;
    _at = null;
  }

  /// 从已有本地路径复制（优先，不必再写一遍临时文件）。
  static Future<void> writePath(
    String path, {
    required String fileName,
    Uint8List? bytes,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw StateError('empty path');
    }
    ChatImageClipboard.clear();
    final name = fileName.trim().isEmpty
        ? trimmed.replaceAll('\\', '/').split('/').last
        : fileName.trim();
    final gen = ++_writeGen;
    _bytes = (bytes != null && bytes.isNotEmpty) ? bytes : Uint8List(0);
    _fileName = name;
    _localPath = trimmed;
    _at = DateTime.now();
    unawaited(_syncFromPath(trimmed, name, gen, seedBytes: bytes));
  }

  /// 从字节复制（无本地缓存时）。
  static Future<void> write(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('empty file');
    }
    ChatImageClipboard.clear();
    final name = fileName.trim().isEmpty ? 'file.bin' : fileName.trim();
    final gen = ++_writeGen;
    _bytes = bytes;
    _fileName = name;
    _localPath = null;
    _at = DateTime.now();
    unawaited(_syncFromBytes(bytes, name, gen));
  }

  static Future<void> _syncFromPath(
    String path,
    String name,
    int gen, {
    Uint8List? seedBytes,
  }) async {
    if (gen != _writeGen) return;
    try {
      await io.writeLocalPathToClipboard(path);
    } catch (e) {
      debugPrint('[ChatFileClipboard] path write failed: $e');
    }
    if (gen != _writeGen) return;
    if (seedBytes != null && seedBytes.isNotEmpty) {
      _bytes = seedBytes;
      return;
    }
    try {
      final data = await io.readLocalFileBytes(path);
      if (gen != _writeGen) return;
      if (data.isNotEmpty) {
        _bytes = data;
        _at = DateTime.now();
      }
    } catch (e) {
      debugPrint('[ChatFileClipboard] read path failed: $e');
    }
  }

  static Future<void> _syncFromBytes(
    Uint8List bytes,
    String name,
    int gen,
  ) async {
    if (gen != _writeGen) return;
    try {
      final path = await io.writeBytesFileToClipboard(bytes, fileName: name);
      if (gen != _writeGen) return;
      if (path != null && path.isNotEmpty) {
        _localPath = path;
      }
    } catch (e) {
      debugPrint('[ChatFileClipboard] bytes write failed: $e');
    }
  }
}
