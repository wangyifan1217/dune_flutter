import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';

/// 将会话读写串行化，避免旧会话的异步删除覆盖刚完成的登录。
///
/// 登录记录写两份：系统偏好，以及应用目录里的独立文件。部分安卓机把偏好文件
/// 写到一半杀掉进程后，系统会丢掉整份偏好；独立文件还在时，下次启动可以恢复。
class AuthSessionStorage {
  AuthSessionStorage({
    Future<SharedPreferences> Function()? preferences,
    Future<Directory?> Function()? sessionDirectory,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _sessionDirectory = sessionDirectory ?? _defaultSessionDirectory;

  static const key = 'dunes_auth_session_v1';
  static const _fileName = 'dunes_auth_session_v1.json';
  static final AuthSessionStorage instance = AuthSessionStorage();
  final Future<SharedPreferences> Function() _preferences;
  final Future<Directory?> Function() _sessionDirectory;
  Future<void> _tail = Future<void>.value();

  static Future<Directory?> _defaultSessionDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }

  Future<String?> read() => _enqueue(_readBest);

  Future<void> write(AuthSession session, {bool Function()? stillCurrent}) =>
      _enqueue(() async {
        if (stillCurrent != null && !stillCurrent()) return;
        final raw = jsonEncode(session.toJson());
        var saved = false;
        try {
          await _writeMirror(raw);
          saved = true;
        } catch (_) {}
        try {
          final prefs = await _preferences();
          if (stillCurrent != null && !stillCurrent()) return;
          if (await prefs.setString(key, raw)) saved = true;
        } catch (_) {}
        if (!saved) throw StateError('保存登录状态失败');
      });

  Future<void> removeIfToken(String token) => _enqueue(() async {
    if (token.isEmpty) return;
    final dir = await _sessionDirectory();
    final fileToken = _tokenOf(await _readNamed(dir, _fileName));
    final prefs = await _tryPrefs();
    final prefsToken = _tokenOf(prefs?.getString(key));
    if ((fileToken ?? prefsToken) != token) return;
    await _deleteMirror(dir);
    if (prefs != null && !await prefs.remove(key)) {
      throw StateError('清除登录状态失败');
    }
  });

  /// 丢掉本地登录记录。偏好和独立文件一起删。
  Future<void> clear() => _enqueue(() async {
    final dir = await _sessionDirectory();
    await _deleteMirror(dir);
    final prefs = await _tryPrefs();
    if (prefs != null) await prefs.remove(key);
  });

  Future<String?> _readBest() async {
    final dir = await _sessionDirectory();
    final fileRaw = _usable(await _readNamed(dir, _fileName));
    if (fileRaw != null) {
      await _ensurePrefs(fileRaw);
      return fileRaw;
    }
    final prefsRaw = _usable((await _tryPrefs())?.getString(key));
    if (prefsRaw != null) {
      try {
        await _writeMirror(prefsRaw);
      } catch (_) {}
      return prefsRaw;
    }
    final backupRaw = _usable(await _readNamed(dir, '$_fileName.bak'));
    if (backupRaw != null) {
      try {
        await _writeMirror(backupRaw);
      } catch (_) {}
      await _ensurePrefs(backupRaw);
      return backupRaw;
    }
    return null;
  }

  Future<void> _ensurePrefs(String raw) async {
    try {
      final prefs = await _preferences();
      if (prefs.getString(key) == raw) return;
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await _preferences();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readNamed(Directory? dir, String name) async {
    if (dir == null) return null;
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    try {
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeMirror(String raw) async {
    final dir = await _sessionDirectory();
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
    final backup = File('${file.path}.bak');
    final current = _usable(await _readNamed(dir, _fileName));
    if (current != null && current != raw) {
      await backup.writeAsString(current, flush: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(raw, flush: true);
    // 安卓/iOS 上 rename 会原子替换旧文件。先删再改名会留下两份都不在的窗口，
    // 进程恰好在这时被杀，下次启动就读不到登录记录。
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  Future<void> _deleteMirror(Directory? dir) async {
    if (dir == null) return;
    for (final name in [_fileName, '$_fileName.bak', '$_fileName.tmp']) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  static String? _usable(String? raw) {
    final token = _tokenOf(raw);
    if (token == null) return null;
    return raw;
  }

  static String? _tokenOf(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final token = decoded['token'];
      if (token is! String || token.isEmpty) return null;
      return token;
    } catch (_) {
      return null;
    }
  }
}
