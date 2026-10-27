import 'dart:io';
import 'dart:typed_data';

import 'package:dunes_app/features/chat/sticker_disk_cache_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sticker bytes survive a new store pointed at the same directory',
    () async {
      final dir = await Directory.systemTemp.createTemp('sticker-cache-test');
      addTearDown(() => dir.delete(recursive: true));
      final bytes = Uint8List.fromList([1, 2, 3, 9, 9]);
      final first = StickerDiskStore(directory: dir, maxBytes: 1024);
      await first.write('packs/a.png', bytes);
      final second = StickerDiskStore(directory: dir, maxBytes: 1024);
      expect(await second.read('packs/a.png'), bytes);
      expect(await second.read('missing'), isNull);
    },
  );

  test(
    'sticker cache drops the oldest file once the size cap is exceeded',
    () async {
      final dir = await Directory.systemTemp.createTemp('sticker-cache-trim');
      addTearDown(() => dir.delete(recursive: true));
      final store = StickerDiskStore(directory: dir, maxBytes: 5);
      await store.write('old', Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.write('new', Uint8List.fromList([4, 5, 6, 7]));
      expect(await store.read('old'), isNull);
      expect(await store.read('new'), Uint8List.fromList([4, 5, 6, 7]));
    },
  );
}
