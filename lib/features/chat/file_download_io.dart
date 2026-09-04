import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../conversation/conversation_service.dart';
import 'im_cached_file_names.dart';
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

String _safeFileName(String fileName) => safeChatFileName(fileName);

String _safeFolderName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'unknown';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _uniqueFilePath(Directory dir, String fileName) {
  final name = uniqueChatFileName(fileName, (candidate) {
    return File('${dir.path}${Platform.pathSeparator}$candidate').existsSync();
  });
  return '${dir.path}${Platform.pathSeparator}$name';
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

/// 现行布局：`{会话文件夹}/{fileName}`，不再为每个文件建 hash 子目录。
String _conversationCachedFilePath(
  Directory dir,
  int conversationId,
  String fileName,
) {
  return '${_conversationFolderPath(dir, conversationId)}${Platform.pathSeparator}${_safeFileName(fileName)}';
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
  if (conversationId != null && conversationId > 0) {
    final indexed = await _indexedCachedPath(
      dir,
      conversationId: conversationId,
      cacheKey: cacheKey,
    );
    if (indexed != null) return indexed;
    if (cacheKey.isNotEmpty) {
      final hashed = _hashedConversationCachedFilePath(
        dir,
        conversationId,
        cacheKey,
        fileName,
      );
      final hashedFile = File(hashed);
      if (await hashedFile.exists() && await hashedFile.length() > 0) {
        return hashed;
      }
      // cacheKey 在时不再用「仅文件名」命中，避免同名另一份附件打开成旧文件。
    } else {
      final flat = _conversationCachedFilePath(dir, conversationId, fileName);
      final flatFile = File(flat);
      if (await flatFile.exists() && await flatFile.length() > 0) return flat;
    }
  }
  if (cacheKey.isNotEmpty) {
    final legacy = _legacyCachedFilePath(dir, cacheKey, fileName);
    final file = File(legacy);
    if (await file.exists() && await file.length() > 0) return legacy;
  }
  return null;
}

const _imIndexFileName = '.dunes-im-index.json';

File _imIndexFile(Directory convDir) {
  return File('${convDir.path}${Platform.pathSeparator}$_imIndexFileName');
}

Future<Map<String, String>> _loadImIndex(Directory convDir) async {
  final file = _imIndexFile(convDir);
  try {
    if (!await file.exists()) return <String, String>{};
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return <String, String>{};
    final files = raw['files'];
    if (files is! Map) return <String, String>{};
    final out = <String, String>{};
    files.forEach((key, value) {
      final k = key.toString().trim();
      final v = value.toString().trim();
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    });
    return out;
  } catch (_) {
    return <String, String>{};
  }
}

Future<void> _saveImIndex(Directory convDir, Map<String, String> index) async {
  await convDir.create(recursive: true);
  final payload = <String, dynamic>{'v': 1, 'files': index};
  await _imIndexFile(convDir).writeAsString(jsonEncode(payload), flush: true);
}

Future<String?> _indexedCachedPath(
  Directory root, {
  required int conversationId,
  required String cacheKey,
}) async {
  final key = cacheKey.trim();
  if (key.isEmpty) return null;
  final convDir = Directory(_conversationFolderPath(root, conversationId));
  final index = await _loadImIndex(convDir);
  final name = (index[key] ?? '').trim();
  if (name.isEmpty) return null;
  final path = '${convDir.path}${Platform.pathSeparator}$name';
  final file = File(path);
  if (await file.exists() && await file.length() > 0) return path;
  return null;
}

bool _isFileBusyError(Object error) {
  if (error is FileSystemException) {
    final code = error.osError?.errorCode ?? 0;
    // Win32: 32 sharing, 33 lock。POSIX: 16 EBUSY, 26 ETXTBSY。
    if (code == 32 || code == 33 || code == 16 || code == 26) return true;
    final msg = '${error.message} ${error.osError ?? ''}'.toLowerCase();
    if (msg.contains('being used') ||
        msg.contains('sharing violation') ||
        msg.contains('cannot access the file') ||
        msg.contains('locked')) {
      return true;
    }
  }
  final text = error.toString().toLowerCase();
  return text.contains('being used') ||
      text.contains('sharing violation') ||
      text.contains('locked');
}

Future<void> _writeBytesAllowingRename({
  required Directory dir,
  required String basename,
  required Uint8List bytes,
}) async {
  final path = '${dir.path}${Platform.pathSeparator}$basename';
  await Directory(File(path).parent.path).create(recursive: true);
  await File(path).writeAsBytes(bytes, flush: true);
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
  if (conversationId == null || conversationId <= 0) {
    if (key.isEmpty) return saveBytesAsFileImpl(bytes, fileName);
    final parent = Directory(File(_legacyCachedFilePath(dir, key, fileName)).parent.path);
    return _writeWithBusyFallback(
      dir: parent,
      preferredName: _safeFileName(fileName),
      originalFileName: fileName,
      bytes: bytes,
    );
  }

  final convDir = Directory(_conversationFolderPath(dir, conversationId));
  await convDir.create(recursive: true);
  final index = key.isEmpty ? <String, String>{} : await _loadImIndex(convDir);
  var existsCache = <String, bool>{};
  bool exists(String name) {
    return existsCache.putIfAbsent(
      name,
      () => File('${convDir.path}${Platform.pathSeparator}$name').existsSync(),
    );
  }

  var targetName = allocateCachedChatFileName(
    fileName: fileName,
    cacheKey: key,
    index: index,
    exists: exists,
  );
  try {
    await _writeBytesAllowingRename(
      dir: convDir,
      basename: targetName,
      bytes: bytes,
    );
  } catch (e) {
    if (!_isFileBusyError(e)) rethrow;
    existsCache[targetName] = true;
    final renamed = uniqueChatFileName(fileName, exists);
    if (renamed == targetName) rethrow;
    await _writeBytesAllowingRename(
      dir: convDir,
      basename: renamed,
      bytes: bytes,
    );
    targetName = renamed;
  }
  if (key.isNotEmpty) {
    index[key] = targetName;
    await _saveImIndex(convDir, index);
  }
  final path = '${convDir.path}${Platform.pathSeparator}$targetName';
  await _deleteLegacyHashedCopy(
    dir,
    cacheKey: key,
    fileName: fileName,
    conversationId: conversationId,
    keepPath: path,
  );
  return path;
}

Future<String> _writeWithBusyFallback({
  required Directory dir,
  required String preferredName,
  required String originalFileName,
  required Uint8List bytes,
}) async {
  try {
    await _writeBytesAllowingRename(
      dir: dir,
      basename: preferredName,
      bytes: bytes,
    );
    return '${dir.path}${Platform.pathSeparator}$preferredName';
  } catch (e) {
    if (!_isFileBusyError(e)) rethrow;
    final renamed = uniqueChatFileName(originalFileName, (name) {
      return File('${dir.path}${Platform.pathSeparator}$name').existsSync();
    });
    await _writeBytesAllowingRename(dir: dir, basename: renamed, bytes: bytes);
    return '${dir.path}${Platform.pathSeparator}$renamed';
  }
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

/// 新文件已落到会话文件夹后，清掉旧版「一文件一 hash 子目录」。
Future<void> _deleteLegacyHashedCopy(
  Directory dir, {
  required String cacheKey,
  required String fileName,
  int? conversationId,
  required String keepPath,
}) async {
  if (conversationId == null || conversationId <= 0 || cacheKey.isEmpty) return;
  final old = File(
    _hashedConversationCachedFilePath(dir, conversationId, cacheKey, fileName),
  );
  if (old.path == keepPath) return;
  try {
    if (await old.exists()) await old.delete();
    final parent = old.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  } catch (_) {}
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
