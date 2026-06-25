import 'dart:typed_data';

import 'gallery_save_stub.dart'
    if (dart.library.html) 'gallery_save_web.dart'
    if (dart.library.io) 'gallery_save_io.dart';

/// 将图片字节保存到系统相册（移动端）/ 触发浏览器下载（Web）。
Future<void> saveImageToGallery(Uint8List bytes, String fileName) =>
    saveImageToGalleryImpl(bytes, fileName);
