import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import 'chat_image_clipboard_io.dart'
    if (dart.library.html) 'chat_image_clipboard_stub.dart' as io;

/// 会话内「复制图片 → 粘贴发送」剪贴板。
///
/// 复制路径刻意做成「先内存、后系统」：
/// - 内存写入同步完成，界面立刻可提示「已复制」
/// - 系统剪贴板（PowerShell / pasteboard）放到后台，避免卡 UI
class ChatImageClipboard {
  ChatImageClipboard._();

  static Uint8List? _bytes;
  static String _fileName = 'image.png';
  static DateTime? _at;
  static int _writeGen = 0;

  static bool get hasImage {
    final at = _at;
    final bytes = _bytes;
    if (at == null || bytes == null || bytes.isEmpty) return false;
    if (DateTime.now().difference(at) > const Duration(hours: 2)) {
      clear();
      return false;
    }
    return true;
  }

  static ({Uint8List bytes, String fileName})? peek() {
    if (!hasImage) return null;
    return (bytes: _bytes!, fileName: _fileName);
  }

  static void clear() {
    _writeGen++;
    _bytes = null;
    _fileName = 'image.png';
    _at = null;
  }

  /// 同步写入进程内备份，并异步刷系统剪贴板（不阻塞调用方）。
  static Future<void> write(
    Uint8List bytes, {
    String fileName = 'image.png',
  }) async {
    if (bytes.isEmpty) {
      throw StateError('empty image');
    }
    final name = _clipboardFileName(fileName, bytes);
    final gen = ++_writeGen;
    _bytes = bytes;
    _fileName = name;
    _at = DateTime.now();
    unawaited(_syncSystemClipboard(bytes, name, gen));
  }

  static Future<void> _syncSystemClipboard(
    Uint8List bytes,
    String name,
    int gen,
  ) async {
    // 已被更新的复制覆盖，跳过过期写入。
    if (gen != _writeGen) return;
    try {
      await io.writeImageFileToClipboard(bytes, fileName: name);
    } catch (e) {
      debugPrint('[ChatImageClipboard] platform write failed: $e');
    }
    if (gen != _writeGen) return;
    try {
      await Pasteboard.writeImage(bytes);
    } catch (e) {
      debugPrint('[ChatImageClipboard] writeImage failed: $e');
    }
  }

  static String _clipboardFileName(String fileName, Uint8List bytes) {
    final trimmed = fileName.trim();
    if (trimmed.isNotEmpty) {
      final lower = trimmed.toLowerCase();
      if (lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.bmp')) {
        return trimmed;
      }
    }
    if (_isPng(bytes)) return 'image.png';
    if (_isJpeg(bytes)) return 'image.jpg';
    if (_isGif(bytes)) return 'image.gif';
    if (_isWebp(bytes)) return 'image.webp';
    if (_isBmp(bytes)) return 'image.bmp';
    return trimmed.isEmpty ? 'image.png' : '$trimmed.png';
  }

  static bool _isPng(Uint8List b) =>
      b.length >= 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  static bool _isJpeg(Uint8List b) =>
      b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8;

  static bool _isGif(Uint8List b) =>
      b.length >= 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;

  static bool _isBmp(Uint8List b) =>
      b.length >= 2 && b[0] == 0x42 && b[1] == 0x4D;

  static bool _isWebp(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[8] == 0x57 &&
      b[9] == 0x45;
}
