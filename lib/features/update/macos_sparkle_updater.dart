import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../desktop/windows_desktop_tray.dart';

/// macOS Sparkle 桥：现有 API 弹窗点「立即更新」后交给原生验签/替换/重启。
class MacosSparkleUpdater {
  MacosSparkleUpdater._();

  static final instance = MacosSparkleUpdater._();

  static const _channel = MethodChannel('nova.dunes/sparkle_updater');

  bool _handlerReady = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  void _ensureHandler() {
    if (_handlerReady || !isSupported) return;
    _handlerReady = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'prepareForQuit':
          // Sparkle 即将安装/重启：必须先解除 preventClose，否则 terminate 会被取消。
          await windowsTrayPrepareQuitForAppUpdate(exitProcess: false);
          return null;
        case 'rearmPreventClose':
          await windowsTrayRearmPreventCloseAfterUpdateCancelled();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  Future<bool> probeSupported() async {
    if (!isSupported) return false;
    _ensureHandler();
    try {
      final value = await _channel.invokeMethod<bool>('isSupported');
      return value == true;
    } catch (_) {
      return false;
    }
  }

  /// 拉起 Sparkle 检查 Appcast 并安装；失败抛出异常供弹窗提示。
  Future<void> checkForUpdates() async {
    if (!isSupported) {
      throw StateError('仅 macOS 支持 Sparkle 应用内更新');
    }
    _ensureHandler();
    // 用户已在 Flutter 弹窗确认更新：先松绑，避免 Sparkle「安装并重启」时
    // window_manager preventClose 取消 NSApp.terminate。
    await windowsTrayPrepareQuitForAppUpdate(exitProcess: false);
    await _channel.invokeMethod<void>('checkForUpdates');
  }
}
