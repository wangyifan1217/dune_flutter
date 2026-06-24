import 'dart:typed_data';

import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart'
    if (dart.library.io) 'file_download_io.dart';

Future<void> saveBytesAsFile(Uint8List bytes, String fileName) =>
    saveBytesAsFileImpl(bytes, fileName);

Future<void> openUrlAsFile(String url, String fileName) =>
    openUrlAsFileImpl(url, fileName);
