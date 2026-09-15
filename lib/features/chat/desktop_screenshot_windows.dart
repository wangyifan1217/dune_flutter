import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:just_screenshot/screenshot.dart';

bool _regionCaptureBusy = false;

/// Windows：应用内冻屏框选（just_screenshot），对齐微信 PC。
Future<Uint8List?> captureWindowsRegionScreenshot() async {
  if (_regionCaptureBusy) return null;
  _regionCaptureBusy = true;
  try {
    final CapturedData? data = await Screenshot.instance.capture(
      mode: ScreenshotMode.region,
    );
    if (data == null || data.bytes.isEmpty) return null;
    return data.bytes;
  } on ScreenshotException catch (e) {
    if (e.code == 'cancelled') return null;
    rethrow;
  } finally {
    _regionCaptureBusy = false;
  }
}

/// Windows 全局热键 Ctrl+Alt+A。
/// 注意：只注册一次；切换会话只替换回调，禁止 unregister（会触发原生 abort）。
class WindowsScreenshotHotkey {
  WindowsScreenshotHotkey._();

  static HotKey? _hotKey;
  static VoidCallback? _handler;
  static bool _registering = false;

  static Future<void> ensureRegistered(VoidCallback onPressed) async {
    _handler = onPressed;
    if (_hotKey != null || _registering) return;
    _registering = true;
    try {
      final key = HotKey(
        key: PhysicalKeyboardKey.keyA,
        modifiers: const <HotKeyModifier>[
          HotKeyModifier.control,
          HotKeyModifier.alt,
        ],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        key,
        keyDownHandler: (_) {
          _handler?.call();
        },
      );
      _hotKey = key;
    } catch (e, st) {
      debugPrint('[ScreenshotHotkey] register failed: $e\n$st');
    } finally {
      _registering = false;
    }
  }

  /// 仅清回调，不卸载系统热键（避免切会话崩溃）。
  static void clear(VoidCallback onPressed) {
    if (_handler == onPressed) {
      _handler = null;
    }
  }
}
