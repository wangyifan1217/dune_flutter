import 'dart:typed_data';

import 'package:gal/gal.dart';

Future<void> saveImageToGalleryImpl(Uint8List bytes, String fileName) async {
  final hasAccess = await Gal.hasAccess();
  if (!hasAccess) {
    final granted = await Gal.requestAccess();
    if (!granted) {
      throw Exception('未授予相册访问权限');
    }
  }
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  await Gal.putImageBytes(bytes, name: name.isEmpty ? 'image' : name);
}
