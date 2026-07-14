import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/desktop_features.dart';
import 'app_update_service.dart';

typedef UpdateDownloadProgress = void Function(double progress);

/// 桌面端应用内下载安装包并拉起安装程序；移动端仍走浏览器 / 应用商店页。
class AppUpdateInstaller {
  const AppUpdateInstaller._();

  static const instance = AppUpdateInstaller._();

  static const _macOpenTimeout = Duration(seconds: 20);

  bool get supportsInAppInstall => isDesktopCommOnly;

  Future<void> applyUpdate(
    AppReleaseCheckResult result, {
    UpdateDownloadProgress? onProgress,
    VoidCallback? onLaunching,
  }) async {
    final url = result.downloadUrl.trim();
    if (url.isEmpty) {
      throw StateError('下载地址为空');
    }
    if (!supportsInAppInstall) {
      await _openExternal(url);
      return;
    }

    final file = await downloadInstaller(url, onProgress: onProgress);
    onLaunching?.call();
    await launchInstaller(file);
  }

  Future<File> downloadInstaller(
    String url, {
    UpdateDownloadProgress? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final dir = await getTemporaryDirectory();
    final name = _fileNameFromUri(uri);
    final target = File('${dir.path}${Platform.pathSeparator}$name');
    if (await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', uri);
      final resp = await client.send(req).timeout(const Duration(minutes: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('下载失败 HTTP ${resp.statusCode}', uri: uri);
      }
      final total = resp.contentLength ?? -1;
      final sink = target.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        } else {
          onProgress?.call(-1);
        }
      }
      await sink.flush();
      await sink.close();
      if (received <= 0 || await target.length() <= 0) {
        throw StateError('下载文件为空');
      }
      onProgress?.call(1);
      return target;
    } finally {
      client.close();
    }
  }

  Future<void> launchInstaller(File file) async {
    if (!await file.exists()) {
      throw StateError('安装包不存在');
    }
    final path = file.path;
    if (Platform.isWindows) {
      // 分离进程启动安装器，再退出当前进程以便覆盖文件。
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      // 稍等安装器起来
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    }
    if (Platform.isMacOS) {
      await _launchMacInstaller(path);
      return;
    }
    await _openExternal(path);
  }

  /// Mac：用 `open` 挂载/打开 DMG。不无限等待，避免 UI 卡在 100%。
  Future<void> _launchMacInstaller(String path) async {
    final file = File(path);
    if (await file.length() <= 0) {
      throw StateError('安装包无效');
    }

    try {
      // 分离启动，避免阻塞在 Gatekeeper / 挂载过程。
      await Process.start(
        'open',
        [path],
        mode: ProcessStartMode.detached,
      ).timeout(_macOpenTimeout);
    } on TimeoutException {
      // 已交给系统；超时仍视为已发起打开，由 UI 引导用户手动安装。
      return;
    } catch (_) {
      // 分离启动失败时回退到同步 open，并限制等待时间。
      try {
        final result = await Process.run(
          'open',
          [path],
        ).timeout(_macOpenTimeout);
        if (result.exitCode != 0) {
          throw ProcessException(
            'open',
            [path],
            result.stderr.toString(),
            result.exitCode,
          );
        }
      } on TimeoutException {
        return;
      }
    }
  }

  Future<void> _openExternal(String urlOrPath) async {
    final uri = urlOrPath.startsWith('http')
        ? Uri.parse(urlOrPath)
        : Uri.file(urlOrPath);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开下载地址');
    }
  }

  String _fileNameFromUri(Uri uri) {
    final raw = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final decoded = Uri.decodeComponent(raw).trim();
    if (decoded.isNotEmpty && decoded.contains('.')) {
      return decoded.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return 'DunesSetup.dmg';
    }
    return 'DunesSetup.exe';
  }
}
