import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> writeChatVoiceTempFileImpl(
  Uint8List bytes, {
  String fileName = 'voice.m4a',
}) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final path =
      '${dir.path}${Platform.pathSeparator}chat_voice_${DateTime.now().millisecondsSinceEpoch}_$safe';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
