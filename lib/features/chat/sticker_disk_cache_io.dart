import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

const stickerDiskCacheMaxBytes = 120 * 1024 * 1024;

final Map<String, Future<Uint8List>> _inflight = {};
StickerDiskStore? _store;

Future<Uint8List> loadStickerBytes(
  String objectKey,
  Future<Uint8List> Function() download, {
  StickerDiskStore? store,
}) {
  final key = objectKey.trim();
  if (key.isEmpty) return download();
  return _inflight.putIfAbsent(key, () async {
    try {
      final disk = store ?? await _defaultStore();
      final cached = await disk.read(key);
      if (cached != null && cached.isNotEmpty) return cached;
      final bytes = await download();
      if (bytes.isNotEmpty) {
        try {
          await disk.write(key, bytes);
        } catch (_) {}
      }
      return bytes;
    } catch (error) {
      _inflight.remove(key);
      rethrow;
    }
  });
}

Future<StickerDiskStore> _defaultStore() async {
  final existing = _store;
  if (existing != null) return existing;
  final root = await getApplicationSupportDirectory();
  final dir = Directory('${root.path}${Platform.pathSeparator}sticker-cache');
  final created = StickerDiskStore(directory: dir);
  _store = created;
  return created;
}

/// 文件名用稳定哈希，避免 objectKey 里的斜杠写进路径。
String stickerCacheFileName(String objectKey) {
  var hash = 0xcbf29ce484222325;
  for (final unit in objectKey.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

class StickerDiskStore {
  StickerDiskStore({
    required this.directory,
    this.maxBytes = stickerDiskCacheMaxBytes,
  });

  final Directory directory;
  final int maxBytes;
  Future<void> _writes = Future<void>.value();

  Future<Uint8List?> read(String objectKey) async {
    final file = _file(objectKey);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final now = DateTime.now();
    try {
      await file.setLastModified(now);
    } catch (_) {}
    return bytes;
  }

  Future<void> write(String objectKey, Uint8List bytes) {
    final operation = _writes.then((_) async {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = _file(objectKey);
      await file.writeAsBytes(bytes, flush: true);
      await _trim();
    });
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  File _file(String objectKey) => File(
    '${directory.path}${Platform.pathSeparator}${stickerCacheFileName(objectKey)}',
  );

  Future<void> _trim() async {
    if (!await directory.exists()) return;
    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File) files.add(entity);
    }
    final stats = <({File file, int size, DateTime touched})>[];
    var total = 0;
    for (final file in files) {
      final stat = await file.stat();
      total += stat.size;
      stats.add((file: file, size: stat.size, touched: stat.modified));
    }
    stats.sort((a, b) => a.touched.compareTo(b.touched));
    for (final item in stats) {
      if (total <= maxBytes) return;
      try {
        await item.file.delete();
        total -= item.size;
      } catch (_) {}
    }
  }
}
