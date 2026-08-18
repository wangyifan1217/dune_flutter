import 'package:flutter/foundation.dart';

List<String> existingLocalFilePaths(List<String> paths) => const [];

Future<Uint8List> readLocalFileBytes(String filePath) async => Uint8List(0);

Future<void> writeLocalPathToClipboard(String filePath) async {}

Future<String?> writeBytesFileToClipboard(
  Uint8List bytes, {
  required String fileName,
}) async {
  return null;
}
