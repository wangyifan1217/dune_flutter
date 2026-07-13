import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

const _trayIconWin = 'assets/images/tray_icon.ico';
const _trayIconWinBlank = 'assets/images/tray_icon_blank.ico';
const _trayIconMac = 'assets/images/tray_icon.png';
const _trayIconMacBlank = 'assets/images/tray_icon_blank.png';

Future<void> initWindowsDesktopTray() => WindowsDesktopTray.instance.init();

void windowsTrayUpdateUnread(int total) {
  WindowsDesktopTray.instance.updateUnread(total);
}

void windowsTrayNotifyIncomingMessage() {
  WindowsDesktopTray.instance.notifyIncomingMessage();
}

void setWindowsTrayOnBeforeQuit(Future<void> Function()? callback) {
  WindowsDesktopTray.instance.onBeforeQuit = callback;
}

/// 关闭进托盘；隐藏且有未读/新消息时托盘图标闪烁。
class WindowsDesktopTray with WindowListener, TrayListener {
  WindowsDesktopTray._();
  static final WindowsDesktopTray instance = WindowsDesktopTray._();

  bool _ready = false;
  bool _hidden = false;
  bool _allowQuit = false;
  bool _flashing = false;
  bool _flashVisible = true;
  bool _pendingAlert = false;
  int _unread = 0;
  Timer? _flashTimer;
  String _trayIcon = _trayIconWin;
  String _trayIconBlank = _trayIconWinBlank;
  Future<void> Function()? onBeforeQuit;

  Future<void> init() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS) || _ready) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // 默认宽窗，保证进入双栏聊天布局（≥900）；可再拖拽缩放。
    const windowOptions = WindowOptions(
      size: Size(1180, 760),
      minimumSize: Size(960, 640),
      center: true,
      skipTaskbar: false,
      title: '沙丘',
    );

    // 窗口就绪后再拦截关闭，避免插件尚未挂上 HWND 时点 X 直接退出。
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.setTitle('沙丘');
      await windowManager.show();
      await windowManager.focus();
    });

    await windowManager.setPreventClose(true);

    if (Platform.isMacOS) {
      // macOS 托盘更稳妥用 png；暂无 blank 资源时闪烁仍切换同一图标（无害）。
      _trayIcon = _trayIconMac;
      _trayIconBlank = _trayIconMacBlank;
    } else {
      _trayIcon = _trayIconWin;
      _trayIconBlank = _trayIconWinBlank;
    }

    await trayManager.setIcon(_trayIcon);
    await trayManager.setToolTip('沙丘');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '打开沙丘'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );
    trayManager.addListener(this);
    if (Platform.isMacOS) {
      await windowManager.setPreventClose(true);
    }
    _ready = true;
  }

  void updateUnread(int total) {
    if (!_ready) return;
    _unread = total < 0 ? 0 : total;
    if (_unread == 0) _pendingAlert = false;
    unawaited(_syncFlash());
  }

  void notifyIncomingMessage() {
    if (!_ready || !_hidden) return;
    _pendingAlert = true;
    unawaited(_syncFlash());
  }

  Future<void> _hideToTray() async {
    _hidden = true;
    // 再次确保关闭被拦截（部分时机下可能被重置）。
    await windowManager.setPreventClose(true);
    await windowManager.hide();
    // Windows：从任务栏隐藏；macOS：从 Dock 隐藏，仅留状态栏图标
    await windowManager.setSkipTaskbar(true);
    await _syncFlash();
  }

  Future<void> _showFromTray() async {
    _hidden = false;
    _pendingAlert = false;
    await _stopFlash();
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    if (Platform.isMacOS) {
      // 确保 macOS 前台激活
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
    }
    await windowManager.setPreventClose(true);
    await trayManager.setIcon(_trayIcon);
  }

  Future<void> _quitApp() async {
    _allowQuit = true;
    await _stopFlash();
    try {
      await onBeforeQuit?.call();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    // QuitOnClose=false 时必须主动结束进程。
    exit(0);
  }

  Future<void> _syncFlash() async {
    final shouldFlash = _hidden && (_unread > 0 || _pendingAlert);
    if (shouldFlash) {
      await _startFlash();
    } else {
      await _stopFlash();
    }
    final tip = _unread > 0 ? '沙丘（$_unread 条未读）' : '沙丘';
    try {
      await trayManager.setToolTip(tip);
    } catch (_) {}
  }

  Future<void> _startFlash() async {
    if (_flashing) return;
    _flashing = true;
    _flashVisible = true;
    _flashTimer?.cancel();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      unawaited(_toggleFlashIcon());
    });
  }

  Future<void> _stopFlash() async {
    _flashTimer?.cancel();
    _flashTimer = null;
    _flashing = false;
    _flashVisible = true;
    try {
      await trayManager.setIcon(_trayIcon);
    } catch (_) {}
  }

  Future<void> _toggleFlashIcon() async {
    if (!_flashing) return;
    _flashVisible = !_flashVisible;
    try {
      await trayManager.setIcon(_flashVisible ? _trayIcon : _trayIconBlank);
    } catch (_) {}
  }

  @override
  void onWindowClose() {
    if (_allowQuit) return;
    unawaited(_onCloseRequested());
  }

  Future<void> _onCloseRequested() async {
    try {
      final prevent = await windowManager.isPreventClose();
      if (!prevent) return;
      await _hideToTray();
    } catch (e, st) {
      debugPrint('[Tray] hide on close failed: $e\n$st');
    }
  }

  @override
  void onWindowRestore() {
    _hidden = false;
    _pendingAlert = false;
    unawaited(_stopFlash());
  }

  @override
  void onWindowFocus() {
    if (!_hidden) {
      _pendingAlert = false;
      unawaited(_stopFlash());
    }
  }

  @override
  void onTrayIconMouseDown() {
    // macOS 状态栏单击：显示窗口；Windows 左键同理
    unawaited(_showFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseUp() {
    // macOS 部分版本在 mouseUp 弹出菜单更稳
    if (Platform.isMacOS) {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showFromTray());
        break;
      case 'quit':
        unawaited(_quitApp());
        break;
    }
  }
}
