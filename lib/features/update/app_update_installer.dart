import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/desktop_features.dart';
import '../desktop/windows_desktop_tray.dart';
import 'app_update_service.dart';
import 'macos_sparkle_updater.dart';

typedef UpdateDownloadProgress = void Function(double progress);

class ApplyUpdateOutcome {
  const ApplyUpdateOutcome({
    this.macInstallerPath,
    this.usedSparkle = false,
  });

  /// 兼容旧字段：DMG 兜底路径（Sparkle 成功时为空）。
  final String? macInstallerPath;

  /// macOS 已交给 Sparkle 处理（原生 UI 接管下载/替换）。
  final bool usedSparkle;
}

/// 桌面端应用内更新；移动端仍走浏览器 / 应用商店页。
class AppUpdateInstaller {
  const AppUpdateInstaller._();

  static const instance = AppUpdateInstaller._();

  bool get supportsInAppInstall => isDesktopCommOnly;

  Future<ApplyUpdateOutcome> applyUpdate(
    AppReleaseCheckResult result, {
    UpdateDownloadProgress? onProgress,
    VoidCallback? onLaunching,
  }) async {
    final url = result.downloadUrl.trim();
    if (url.isEmpty && !(Platform.isMacOS && MacosSparkleUpdater.instance.isSupported)) {
      throw StateError('下载地址为空');
    }
    if (!supportsInAppInstall) {
      if (url.isEmpty) throw StateError('下载地址为空');
      await _openExternal(url);
      return const ApplyUpdateOutcome();
    }

    // macOS：优先 Sparkle（Appcast 验签 + 自动替换）；失败再回退浏览器下载。
    if (Platform.isMacOS) {
      onLaunching?.call();
      try {
        final ok = await MacosSparkleUpdater.instance.probeSupported();
        if (ok) {
          await MacosSparkleUpdater.instance.checkForUpdates();
          return const ApplyUpdateOutcome(usedSparkle: true);
        }
      } catch (e) {
        // Sparkle 不可用时若有 downloadUrl，仍允许浏览器兜底。
        if (url.isEmpty) rethrow;
        await _openExternalAndQuitMac(url);
        return const ApplyUpdateOutcome();
      }
      if (url.isEmpty) {
        throw StateError('Sparkle 不可用且下载地址为空');
      }
      await _openExternalAndQuitMac(url);
      return const ApplyUpdateOutcome();
    }

    final file = await downloadInstaller(url, onProgress: onProgress);
    onLaunching?.call();
    // 让 UI 先切到「正在打开…」，避免一直停在下载 100%。
    await Future<void>.delayed(const Duration(milliseconds: 80));

    await launchInstaller(file);
    return const ApplyUpdateOutcome();
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
          // 未收完前最高显示 99%，避免「100% 却仍在写盘/打开」的假卡住感。
          final raw = received / total;
          onProgress?.call(raw >= 1.0 ? 0.99 : raw.clamp(0.0, 0.99));
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
      // 先解除关窗进托盘，避免安装器/Restart Manager 发 WM_CLOSE 时只藏托盘不退出。
      // 不走 onBeforeQuit，保留本地登录态便于安装后恢复会话。
      await windowsTrayPrepareQuitForAppUpdate(exitProcess: false);
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      // 安装器已 detached 启动；尽快退出，缩短与 CloseApplications 的竞态窗口。
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await windowsTrayPrepareQuitForAppUpdate(exitProcess: true);
      return;
    }
    if (Platform.isMacOS) {
      final staged = await _stageMacInstaller(file);
      _spawnDetached('xattr', ['-dr', 'com.apple.quarantine', staged.path]);
      _spawnDetached('open', [staged.path]);
      // 对齐 Windows：打开安装包后退出，避免拖装时占用 .app。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await windowsTrayPrepareQuitForAppUpdate(exitProcess: true);
      return;
    }
    await _openExternal(path);
  }

  /// 浏览器打开 DMG 后退出进程，便于用户安装替换。
  Future<void> _openExternalAndQuitMac(String urlOrPath) async {
    await _openExternal(urlOrPath);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await windowsTrayPrepareQuitForAppUpdate(exitProcess: true);
  }

  /// 把 DMG 放到「下载」目录（仅兜底路径使用）。
  Future<File> _stageMacInstaller(File downloaded) async {
    if (!await downloaded.exists() || await downloaded.length() <= 0) {
      throw StateError('安装包无效');
    }
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } catch (_) {}
    final destDir = downloads ?? await getTemporaryDirectory();
    final name = downloaded.uri.pathSegments.isNotEmpty
        ? downloaded.uri.pathSegments.last
        : 'DunesSetup.dmg';
    final destPath = '${destDir.path}${Platform.pathSeparator}$name';
    if (File(destPath).absolute.path == downloaded.absolute.path) {
      return downloaded;
    }
    final dest = await downloaded.copy(destPath);
    return dest;
  }

  void _spawnDetached(String executable, List<String> arguments) {
    try {
      unawaited(
        Process.start(
          executable,
          arguments,
          mode: ProcessStartMode.detached,
        ),
      );
    } catch (_) {}
  }

  /// 在 Finder 中显示已下载的安装包。
  Future<void> revealInFinder(String path) async {
    if (path.trim().isEmpty) return;
    _spawnDetached('open', ['-R', path]);
  }

  Future<void> openMacInstaller(String path) async {
    if (path.trim().isEmpty) return;
    _spawnDetached('xattr', ['-dr', 'com.apple.quarantine', path]);
    _spawnDetached('open', [path]);
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
