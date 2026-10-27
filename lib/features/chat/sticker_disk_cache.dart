import 'dart:typed_data';

import 'sticker_disk_cache_stub.dart'
    if (dart.library.io) 'sticker_disk_cache_io.dart'
    as impl;

/// 表情包按 objectKey 落在本机。同一张图下次直接读文件，不再要临时地址。
Future<Uint8List> loadStickerBytes(
  String objectKey,
  Future<Uint8List> Function() download,
) => impl.loadStickerBytes(objectKey, download);
