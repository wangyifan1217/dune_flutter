import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'im_egg_artwork_specs.dart';

export 'im_egg_artwork_specs.dart';

/// Pixel artwork exported from the HTML preview, shared by Android and iOS.
class ImEggArtwork {
  ImEggArtwork._();
  static final Map<String, Future<ui.Image?>> _images = {};
  static final Map<String, ui.Image> _decodedImages = {};

  static ui.Image? cached(String glyph) => _decodedImages[glyph];

  static Future<ui.Image?> load(String glyph) =>
      _images.putIfAbsent(glyph, () async {
        final spec = imEggArtworkSpecs[glyph];
        if (spec == null) return null;
        final bytes = await rootBundle.load(spec.$1);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        try {
          final image = (await codec.getNextFrame()).image;
          _decodedImages[glyph] = image;
          return image;
        } finally {
          codec.dispose();
        }
      });
}
