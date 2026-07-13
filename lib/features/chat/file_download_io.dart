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
  // Windows / macOS：放到系统「下载/沙丘文件」，便于 Finder / 资源管理器找到。
  if (Platform.isWindows || Platform.isMacOS) {
    final downloads = await getDownloadsDirectory();
    final base = downloads ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}沙丘文件');
    await dir.create(recursive: true);
    return dir;
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
  var target = File('${dir.path}${Platform.pathSeparator}$safe');
  if (!target.existsSync()) return target.path;
  final dot = safe.lastIndexOf('.');
  final base = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot) : '';
  var i = 1;
  while (true) {
    final candidate =
        File('${dir.path}${Platform.pathSeparator}$base($i)$ext');
    if (!candidate.existsSync()) return candidate.path;
    i += 1;
  }
}

/// 用 objectKey / url 生成稳定子目录，便于二次点击直接打开。
String _cacheFolderName(String cacheKey) {
  // FNV-1a 32-bit：跨进程稳定，避免 String.hashCode 重启后变化。
  var hash = 0x811c9dc5;
  for (final unit in cacheKey.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _cachedFilePath(Directory dir, String cacheKey, String fileName) {
  final folder =
      '${dir.path}${Platform.pathSeparator}${_cacheFolderName(cacheKey)}';
  return '$folder${Platform.pathSeparator}${_safeFileName(fileName)}';
}

Future<String?> findCachedChatFileImpl(String cacheKey, String fileName) async {
  final key = cacheKey.trim();
  if (key.isEmpty) return null;
  final dir = await _resolveSaveDir();
  final path = _cachedFilePath(dir, key, fileName);
  final file = File(path);
  if (await file.exists() && await file.length() > 0) return path;
  return null;
}

Future<String> saveBytesAsCachedFileImpl(
  Uint8List bytes,
  String cacheKey,
  String fileName,
) async {
  final key = cacheKey.trim();
  if (key.isEmpty) {
    return saveBytesAsFileImpl(bytes, fileName);
  }
  final dir = await _resolveSaveDir();
  final path = _cachedFilePath(dir, key, fileName);
  await Directory(File(path).parent.path).create(recursive: true);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
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
  String? cacheKey,
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
    final bytes = Uint8List.fromList(chunks);
    final key = (cacheKey ?? '').trim();
    if (key.isNotEmpty) {
      return saveBytesAsCachedFileImpl(bytes, key, fileName);
    }
    return saveBytesAsFileImpl(bytes, fileName);
  } finally {
    client.close();
  }
}

/// 用系统默认应用打开本地文件（Win / macOS / Linux）。
Future<void> openLocalFileImpl(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw Exception('文件不存在');
  }
  if (Platform.isMacOS) {
    final result = await Process.run('open', [path]);
    if (result.exitCode != 0) {
      throw Exception(
        '无法打开文件：${result.stderr.toString().trim().isEmpty ? '未知错误' : result.stderr}',
      );
    }
    return;
  }
  if (Platform.isWindows) {
    // `start` 第一个引号参数是窗口标题，必须留空才能正确打开带空格路径。
    final result = await Process.run(
      'cmd',
      <String>['/c', 'start', '', path],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
    }
    return;
  }
  if (Platform.isLinux) {
    final result = await Process.run('xdg-open', [path]);
    if (result.exitCode != 0) {
      throw Exception('无法打开文件');
    }
    return;
  }
  throw UnsupportedError('当前平台不支持打开本地文件');
}

/// 在资源管理器 / Finder 中显示文件。
Future<void> revealLocalFileImpl(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw Exception('文件不存在');
  }
  if (Platform.isMacOS) {
    final result = await Process.run('open', ['-R', path]);
    if (result.exitCode != 0) {
      throw Exception('无法在 Finder 中显示');
    }
    return;
  }
  if (Platform.isWindows) {
    final result = await Process.run(
      'explorer.exe',
      <String>['/select,', path],
    );
    if (result.exitCode != 0) {
      throw Exception('无法在资源管理器中显示');
    }
    return;
  }
  // Linux：至少打开所在目录。
  final parent = file.parent.path;
  await Process.run('xdg-open', [parent]);
}
