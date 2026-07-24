import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS Sparkle 桥：现有 API 弹窗点「立即更新」后交给原生验签/替换/重启。
class MacosSparkleUpdater {
  MacosSparkleUpdater._();

  static final instance = MacosSparkleUpdater._();

  static const _channel = MethodChannel('nova.dunes/sparkle_updater');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<bool> probeSupported() async {
    if (!isSupported) return false;
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
    await _channel.invokeMethod<void>('checkForUpdates');
  }
}
