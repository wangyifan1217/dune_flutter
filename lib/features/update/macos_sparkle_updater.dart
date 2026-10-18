import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../desktop/windows_desktop_tray.dart';

/// macOS Sparkle 桥：现有 API 弹窗点「立即更新」后交给原生验签/替换/重启。
class MacosSparkleUpdater {
  MacosSparkleUpdater._();

  static final instance = MacosSparkleUpdater._();

  static const _channel = MethodChannel('nova.dunes/sparkle_updater');

  bool _handlerReady = false;
  Completer<String>? _pending;

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
        case 'updateFound':
          _finish('found');
          return null;
        case 'updateNotFound':
          _finish('error:安装清单里没有新版本。若这里仍提示可更新，说明更新清单还没换成新包');
          return null;
        case 'updateFailed':
          final raw = call.arguments;
          final message = raw is Map ? '${raw['message'] ?? ''}'.trim() : '';
          _finish(
            'error:${message.isEmpty ? '更新检查失败，请稍后重试' : message}',
          );
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
  }

  void _finish(String outcome) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.complete(outcome);
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

  /// 拉起 Sparkle 检查 Appcast。找到新版本后由原生窗口安装；否则抛出原因。
  Future<void> checkForUpdates() async {
    if (!isSupported) {
      throw StateError('仅 macOS 支持 Sparkle 应用内更新');
    }
    _ensureHandler();
    // 用户已在 Flutter 弹窗确认更新：先松绑，避免 Sparkle「安装并重启」时
    // window_manager preventClose 取消 NSApp.terminate。
    await windowsTrayPrepareQuitForAppUpdate(exitProcess: false);
    final pending = Completer<String>();
    _pending = pending;
    try {
      await _channel.invokeMethod<void>('checkForUpdates');
      final outcome = await pending.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => 'error:检查更新超时，请稍后重试',
      );
      if (outcome.startsWith('error:')) {
        throw StateError(outcome.substring('error:'.length));
      }
    } on PlatformException catch (error) {
      final message = (error.message ?? '').trim();
      throw StateError(message.isEmpty ? '无法打开更新程序' : message);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }
}
