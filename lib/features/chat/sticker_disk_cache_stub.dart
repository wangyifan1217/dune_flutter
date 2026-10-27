import 'dart:typed_data';

final Map<String, Future<Uint8List>> _inflight = {};

Future<Uint8List> loadStickerBytes(
  String objectKey,
  Future<Uint8List> Function() download,
) {
  final key = objectKey.trim();
  if (key.isEmpty) return download();
  return _inflight.putIfAbsent(key, () async {
    try {
      return await download();
    } catch (error) {
      _inflight.remove(key);
      rethrow;
    }
  });
}
