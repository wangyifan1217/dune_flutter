import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../conversation/conversation_service.dart';
import 'im_file_save_dir.dart';

Future<Directory> _defaultDesktopSaveDir() async {
  final downloads = await getDownloadsDirectory();
  final base = downloads ?? await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}${Platform.pathSeparator}沙丘文件');
  await dir.create(recursive: true);
  return dir;
}

Future<Directory> _resolveSaveDir() async {
  if (Platform.isAndroid) {
    // 公共 Download/沙丘文件，会话子目录为 conversationId。
    final public = Directory('/storage/emulated/0/Download/沙丘文件');
    try {
      if (!await public.exists()) {
        await public.create(recursive: true);
      }
      return public;
    } catch (_) {
      // Fall back to platform directory when public path is unavailable.
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      final dir = Directory('${downloads.path}${Platform.pathSeparator}沙丘文件');
      await dir.create(recursive: true);
      return dir;
    }
  }
  if (Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/沙丘文件')..createSync(recursive: true);
  }
  // Windows / macOS：优先用户自选目录，否则「下载/沙丘文件」。
  if (Platform.isWindows || Platform.isMacOS) {
    final custom = await ImFileSaveDir.getPath();
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      await dir.create(recursive: true);
      return dir;
    }
    return _defaultDesktopSaveDir();
  }
  return await getApplicationDocumentsDirectory();
}

/// 查找缓存时额外检查的根目录（含默认目录，避免改路径后旧文件打不开）。
Future<List<Directory>> _cacheSearchDirs() async {
  final primary = await _resolveSaveDir();
  final dirs = <Directory>[primary];
  if (Platform.isAndroid) {
    final legacyRoots = <Directory>[
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Download/沙丘文件'),
    ];
    for (final legacy in legacyRoots) {
      if (legacy.path.toLowerCase() != primary.path.toLowerCase()) {
        dirs.add(legacy);
      }
    }
  } else if (Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    final legacy = Directory('${docs.path}/Downloads');
    if (legacy.path != primary.path) dirs.add(legacy);
  } else if (Platform.isWindows || Platform.isMacOS) {
    final fallback = await _defaultDesktopSaveDir();
    if (fallback.path.toLowerCase() != primary.path.toLowerCase()) {
      dirs.add(fallback);
    }
  }
  return dirs;
}

String _safeFileName(String fileName) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return 'download';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _safeFolderName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'unknown';
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
    final candidate = File('${dir.path}${Platform.pathSeparator}$base($i)$ext');
    if (!candidate.existsSync()) return candidate.path;
    i += 1;
  }
}

/// 旧版：用 objectKey / url 的 FNV-1a 哈希做子目录（兼容已下载文件）。
String _legacyCacheFolderName(String cacheKey) {
  var hash = 0x811c9dc5;
  for (final unit in cacheKey.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _conversationFolderPath(Directory dir, int conversationId) {
  return '${dir.path}${Platform.pathSeparator}${_safeFolderName('$conversationId')}';
}

/// 微盘本地下载目录：`{根目录}/企业微盘/{fileName}`（无 hash 子目录）。
const _driveLocalFolderName = '企业微盘';

String _driveFolderPath(Directory dir) {
  return '${dir.path}${Platform.pathSeparator}$_driveLocalFolderName';
}

String _driveCachedFilePath(Directory dir, String fileName) {
  return '${_driveFolderPath(dir)}${Platform.pathSeparator}${_safeFileName(fileName)}';
}

String _legacyCachedFilePath(Directory dir, String cacheKey, String fileName) {
  final folder =
      '${dir.path}${Platform.pathSeparator}${_legacyCacheFolderName(cacheKey)}';
  return '$folder${Platform.pathSeparator}${_safeFileName(fileName)}';
}

String _hashedConversationCachedFilePath(
  Directory dir,
  int conversationId,
  String cacheKey,
  String fileName,
) {
  final folder =
      '${_conversationFolderPath(dir, conversationId)}${Platform.pathSeparator}${_legacyCacheFolderName(cacheKey)}';
  return '$folder${Platform.pathSeparator}${_safeFileName(fileName)}';
}

Future<String?> _findInDir(
  Directory dir, {
  required String cacheKey,
  required String fileName,
  int? conversationId,
}) async {
  if (conversationId != null && conversationId > 0 && cacheKey.isNotEmpty) {
    final path = _hashedConversationCachedFilePath(
      dir,
      conversationId,
      cacheKey,
      fileName,
    );
    final file = File(path);
    if (await file.exists() && await file.length() > 0) return path;
  }
  if (cacheKey.isNotEmpty) {
    final legacy = _legacyCachedFilePath(dir, cacheKey, fileName);
    final file = File(legacy);
    if (await file.exists() && await file.length() > 0) return legacy;
  }
  return null;
}

Future<String?> findCachedChatFileImpl(
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  final key = cacheKey.trim();
  final dirs = await _cacheSearchDirs();
  for (final dir in dirs) {
    final hit = await _findInDir(
      dir,
      cacheKey: key,
      fileName: fileName,
      conversationId: conversationId,
    );
    if (hit != null) return hit;
  }
  return null;
}

Future<String> saveBytesAsCachedFileImpl(
  Uint8List bytes,
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  final key = cacheKey.trim();
  if (key.isEmpty && (conversationId == null || conversationId <= 0)) {
    return saveBytesAsFileImpl(bytes, fileName);
  }
  final dir = await _resolveSaveDir();
  final String path;
  if (conversationId != null && conversationId > 0 && key.isNotEmpty) {
    path = _hashedConversationCachedFilePath(dir, conversationId, key, fileName);
  } else if (key.isNotEmpty) {
    path = _legacyCachedFilePath(dir, key, fileName);
  } else {
    return saveBytesAsFileImpl(bytes, fileName);
  }
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

Future<String> saveBytesAsNovaFileImpl(Uint8List bytes, String fileName) async {
  final root = await _resolveSaveDir();
  final dir = Platform.isAndroid || Platform.isIOS
      ? Directory('${root.path}${Platform.pathSeparator}NOVA')
      : root;
  await dir.create(recursive: true);
  final path = _uniqueFilePath(dir, fileName);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String> openUrlAsFileImpl(
  String url,
  String fileName, {
  void Function(double progress)? onProgress,
  String? cacheKey,
  int? conversationId,
  ChatUploadCancelToken? cancelToken,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) throw Exception('下载链接无效');
  cancelToken?.throwIfCancelled(download: true);
  final client = http.Client();
  cancelToken?.bindClient(client);
  try {
    final req = http.Request('GET', uri);
    final resp = await client.send(req);
    cancelToken?.throwIfCancelled(download: true);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('下载失败（HTTP ${resp.statusCode}）');
    }
    final total = resp.contentLength ?? 0;
    var received = 0;
    final chunks = <int>[];
    await for (final chunk in resp.stream) {
      cancelToken?.throwIfCancelled(download: true);
      chunks.addAll(chunk);
      if (total > 0) {
        received += chunk.length;
        onProgress?.call((received / total).clamp(0.0, 1.0));
      }
    }
    cancelToken?.throwIfCancelled(download: true);
    if (total <= 0) onProgress?.call(1.0);
    final bytes = Uint8List.fromList(chunks);
    final key = (cacheKey ?? '').trim();
    if (key.isNotEmpty || (conversationId != null && conversationId > 0)) {
      return saveBytesAsCachedFileImpl(
        bytes,
        key,
        fileName,
        conversationId: conversationId,
      );
    }
    return saveBytesAsFileImpl(bytes, fileName);
  } on ChatDownloadCancelledException {
    rethrow;
  } catch (e) {
    if (cancelToken?.isCancelled == true) {
      throw const ChatDownloadCancelledException();
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// 用系统默认应用打开本地文件（含 APP 的「用其他应用打开」）。
Future<void> openLocalFileImpl(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw Exception('文件不存在');
  }
  if (Platform.isAndroid || Platform.isIOS) {
    final result = await OpenFilex.open(path);
    if (result.type == ResultType.done) return;
    final msg = result.message.trim();
    throw Exception(msg.isEmpty ? '无法打开文件' : msg);
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
    // explorer 对中文/空格路径比 `cmd /c start` 稳，避免打开失败却只看到兜底文案。
    final explored = await Process.run('explorer.exe', <String>[path]);
    if (explored.exitCode == 0) return;
    final started = await Process.run('cmd', <String>[
      '/c',
      'start',
      '',
      path,
    ], runInShell: false);
    if (started.exitCode == 0) return;
    try {
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return;
    } catch (_) {}
    throw Exception('无法用系统应用打开该文件');
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

Future<void> deleteCachedChatFileImpl(
  String cacheKey,
  String fileName, {
  int? conversationId,
}) async {
  final hit = await findCachedChatFileImpl(
    cacheKey,
    fileName,
    conversationId: conversationId,
  );
  if (hit == null || hit.isEmpty) return;
  final file = File(hit);
  if (await file.exists()) {
    await file.delete();
  }
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
    // `/select,path` 必须是单个参数；explorer.exe 即使成功也常返回非 0，不能据此报错。
    final normalized = path.replaceAll('/', '\\');
    await Process.run('explorer.exe', <String>['/select,$normalized']);
    return;
  }
  // Linux：至少打开所在目录。
  final parent = file.parent.path;
  await Process.run('xdg-open', [parent]);
}

Future<String> resolveImSaveDirPathImpl() async {
  final dir = await _resolveSaveDir();
  return dir.path;
}

Future<String?> saveBytesAsDriveFileImpl(
  Uint8List bytes,
  String fileName, {
  String? cacheKey,
}) async {
  final dir = await _resolveSaveDir();
  final path = _driveCachedFilePath(dir, fileName);
  await Directory(File(path).parent.path).create(recursive: true);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<String?> findCachedDriveFileImpl(
  String fileName, {
  String? cacheKey,
}) async {
  final dirs = await _cacheSearchDirs();
  for (final dir in dirs) {
    final path = _driveCachedFilePath(dir, fileName);
    final file = File(path);
    if (await file.exists() && await file.length() > 0) return path;
  }
  // 兼容旧版 hash 子目录。
  final key = (cacheKey ?? '').trim();
  if (key.isNotEmpty) {
    for (final dir in dirs) {
      final legacy = _legacyCachedFilePath(dir, key, fileName);
      final file = File(legacy);
      if (await file.exists() && await file.length() > 0) return legacy;
    }
  }
  return null;
}
