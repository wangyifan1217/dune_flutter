import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Future<Directory> _resolveSaveDir() async {
  if (Platform.isAndroid) {
    // Prefer public Download so system file pickers can find saved files.
    final public = Directory('/storage/emulated/0/Download');
    try {
      if (!await public.exists()) {
        await public.create(recursive: true);
      }
      return public;
    } catch (_) {
      // Fall back to platform directory when public path is unavailable.
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  }
  if (Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/Downloads')..createSync(recursive: true);
  }
  return await getApplicationDocumentsDirectory();
}

String _safeFileName(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return 'download';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _uniqueFilePath(Directory dir, String fileName) {
  final safe = _safeFileName(fileName);
  var target = File('${dir.path}/$safe');
  if (!target.existsSync()) return target.path;
  final dot = safe.lastIndexOf('.');
  final base = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';
  var i = 1;
  while (true) {
    final candidate = File('${dir.path}/$base($i)$ext');
    if (!candidate.existsSync()) return candidate.path;
    i++;
  }
}

Future<String> saveBytesAsFileImpl(Uint8List bytes, String fileName) async {
  final dir = await _resolveSaveDir();
  final path = _uniqueFilePath(dir, fileName);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String> openUrlAsFileImpl(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('下载链接无效');
  final client = http.Client();
  try {
    final req = http.Request('GET', uri);
    final resp = await client.send(req);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('下载失败（HTTP ${resp.statusCode}）');
    }
    final total = resp.contentLength ?? 0;
    var received = 0;
    final chunks = <int>[];
    await for (final chunk in resp.stream) {
      chunks.addAll(chunk);
      if (total > 0) {
        received += chunk.length;
        onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    }
    if (total <= 0) onProgress?.call(1.0);
    return saveBytesAsFileImpl(Uint8List.fromList(chunks), fileName);
  } finally {
    client.close();
  }
}
