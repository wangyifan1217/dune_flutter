import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:window_manager/window_manager.dart';

const _captureChannel = MethodChannel('dev.flutter.screenshot');

bool _bytesEqual(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  if (a.isEmpty) return true;
  final step = (a.length / 64).ceil().clamp(1, a.length);
  for (var i = 0; i < a.length; i += step) {
    if (a[i] != b[i]) return false;
  }
  return a.first == b.first && a.last == b.last;
}

/// Windows：走系统截图（Win+Shift+S），再从剪贴板取图。
/// 不藏窗、不自研框选，双屏/DPI 由系统处理。
Future<Uint8List?> captureWindowsRegionScreenshot() async {
  Uint8List? before;
  try {
    before = await Pasteboard.image;
  } catch (_) {}

  var launched = false;
  try {
    final ok = await _captureChannel.invokeMethod<bool>('triggerSystemSnip');
    launched = ok == true;
  } catch (_) {
    launched = false;
  }
  if (!launched) {
    try {
      await Process.start(
        'explorer.exe',
        const <String>['ms-screenclip:'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      throw StateError('无法启动系统截图');
    }
  }

  await Future<void>.delayed(const Duration(milliseconds: 450));

  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var sawBlur = false;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 280));

    try {
      final focused = await windowManager.isFocused();
      if (!focused) {
        sawBlur = true;
      } else if (sawBlur) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        final img = await Pasteboard.image;
        if (img != null && img.isNotEmpty && !_bytesEqual(img, before)) {
          return img;
        }
        return null;
      }
    } catch (_) {}

    try {
      final img = await Pasteboard.image;
      if (img != null && img.isNotEmpty && !_bytesEqual(img, before)) {
        return img;
      }
    } catch (_) {}
  }
  return null;
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
