import 'dart:typed_data';

import 'package:dunes_app/features/chat/chat_image_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'large png is resized with the engine instead of blocking on send',
    () async {
      final source = img.Image(width: 960, height: 640);
      var seed = 1;
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          source.setPixelRgb(
            x,
            y,
            seed & 255,
            (seed >> 8) & 255,
            (seed >> 16) & 255,
          );
        }
      }
      final png = Uint8List.fromList(img.encodePng(source));

      final jpeg = await compressChatImageForSend(
        png,
        fileName: 'screenshot.png',
        maxDim: 320,
        quality: 60,
      );

      expect(jpeg, isNotNull);
      expect(jpeg!.length, lessThan(png.length));
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      final decoded = img.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      final longest = decoded!.width > decoded.height
          ? decoded.width
          : decoded.height;
      expect(longest, lessThanOrEqualTo(320));
    },
  );
}
