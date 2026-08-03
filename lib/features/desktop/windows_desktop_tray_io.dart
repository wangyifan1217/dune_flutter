import 'dart:async';
import 'dart:io' show Platform, exit;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/layout/chat_layout.dart';

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

/// 窗口未处于用户可见且聚焦的前台状态。
bool windowsTrayIsWindowInactive() =>
    WindowsDesktopTray.instance.isWindowInactive;

void windowsTrayReveal() {
  unawaited(WindowsDesktopTray.instance.reveal());
}

void setWindowsTrayOnBeforeQuit(Future<void> Function()? callback) {
  WindowsDesktopTray.instance.onBeforeQuit = callback;
}

void setWindowsTrayOnInactiveChanged(void Function(bool inactive)? callback) {
  WindowsDesktopTray.instance.onInactiveChanged = callback;
}

/// 应用更新前解除「关窗进托盘」拦截，使 Sparkle / 安装器能正常终止进程。
/// [exitProcess] 为 true 时走完整退出（DMG 兜底等需立刻腾出 .app 占用）。
Future<void> windowsTrayPrepareQuitForAppUpdate({bool exitProcess = false}) =>
    WindowsDesktopTray.instance.prepareQuitForAppUpdate(
      exitProcess: exitProcess,
    );

/// Sparkle 未真正安装（取消/无更新/失败）时恢复托盘防关闭。
Future<void> windowsTrayRearmPreventCloseAfterUpdateCancelled() =>
    WindowsDesktopTray.instance.rearmPreventCloseAfterUpdateCancelled();

/// 关闭进托盘；最小化/收起到托盘且有未读时托盘图标闪烁。
/// 注意：仅「失焦」不闪烁——Windows 上切窗/弹层会频繁 blur，闪烁会像图标自己狂抖。
class WindowsDesktopTray with WindowListener, TrayListener {
  WindowsDesktopTray._();
  static final WindowsDesktopTray instance = WindowsDesktopTray._();

  bool _ready = false;
  bool _hidden = false;
  bool _minimized = false;
  bool _focused = true;
  bool _allowQuit = false;
  bool _flashing = false;
  bool _flashVisible = true;
  bool _pendingAlert = false;
  int _unread = 0;
  bool? _lastInactiveNotified;
  Timer? _flashTimer;
  Future<void> _iconChain = Future<void>.value();
  bool _iconBusy = false;
  String? _lastIconPath;
  String? _desiredIconPath;
  bool _syncFlashQueued = false;
  String _trayIcon = _trayIconWin;
  String _trayIconBlank = _trayIconWinBlank;
  Future<void> Function()? onBeforeQuit;
  void Function(bool inactive)? onInactiveChanged;

  /// 最小化、失焦和关闭到托盘时，当前会话不应被视为“正在查看”。
  bool get isWindowInactive => _hidden || _minimized || !_focused;

  /// 仅窗口不可见时闪烁托盘（隐藏到托盘或最小化），避免失焦误闪。
  bool get _shouldFlashTray => _hidden || _minimized;

  void _emitInactiveChanged() {
    final inactive = isWindowInactive;
    if (_lastInactiveNotified == inactive) return;
    _lastInactiveNotified = inactive;
    try {
      onInactiveChanged?.call(inactive);
    } catch (_) {}
  }

  Future<void> init() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS) || _ready) return;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // 默认普通窗口（非最大化），可拖拽缩放；最小尺寸高于双栏断点，避免缩成 APP 布局。
    const windowOptions = WindowOptions(
      size: kDesktopWindowDefaultSize,
      minimumSize: kDesktopWindowMinSize,
      center: true,
      skipTaskbar: false,
      title: '沙丘',
    );

    // 窗口就绪后再拦截关闭，避免插件尚未挂上 HWND 时点 X 直接退出。
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.setTitle('沙丘');
      try {
        // WindowOptions 的 minimumSize 在部分系统上不可靠，显式再设一次。
        await windowManager.setMinimumSize(kDesktopWindowMinSize);
        if (await windowManager.isFullScreen()) {
          await windowManager.setFullScreen(false);
        }
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
        await windowManager.setSize(kDesktopWindowDefaultSize);
        await windowManager.center();
      } catch (_) {}
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
    final next = total < 0 ? 0 : total;
    final changed = next != _unread;
    _unread = next;
    if (_unread == 0) _pendingAlert = false;
    // 未读未变且已在正确闪烁/静止态时跳过，避免弱网角标轮询把 setIcon 打爆。
    if (!changed) return;
    _queueSyncFlash();
  }

  void notifyIncomingMessage() {
    // 仅窗口不可见时标记提醒；前台失焦不闪，避免托盘狂抖。
    if (!_ready || !_shouldFlashTray) return;
    if (_pendingAlert && _flashing) return;
    _pendingAlert = true;
    _queueSyncFlash();
  }

  void _queueSyncFlash() {
    if (_syncFlashQueued) return;
    _syncFlashQueued = true;
    scheduleMicrotask(() {
      _syncFlashQueued = false;
      unawaited(_syncFlash());
    });
  }

  Future<void> reveal() => _showFromTray();

  Future<void> _hideToTray() async {
    _hidden = true;
    // 再次确保关闭被拦截（部分时机下可能被重置）。
    await windowManager.setPreventClose(true);
    await windowManager.hide();
    // Windows：从任务栏隐藏；macOS：从 Dock 隐藏，仅留状态栏图标
    await windowManager.setSkipTaskbar(true);
    _emitInactiveChanged();
    _queueSyncFlash();
  }

  Future<void> _showFromTray() async {
    _hidden = false;
    _minimized = false;
    _focused = true;
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
    await _setTrayIcon(_trayIcon);
    _emitInactiveChanged();
  }

  /// Sparkle「安装并重启」前只需松绑；DMG 兜底则 [exitProcess] 立刻退出。
  Future<void> prepareQuitForAppUpdate({bool exitProcess = false}) async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS)) return;
    _allowQuit = true;
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}
    if (!exitProcess) return;
    // 对齐 Windows 更新退出：不走 onBeforeQuit，保留本地登录态便于重装后恢复会话。
    await _stopFlash();
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  /// 用户取消更新或 Sparkle 未安装时，恢复关窗进托盘。
  Future<void> rearmPreventCloseAfterUpdateCancelled() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isMacOS) || !_ready) {
      return;
    }
    _allowQuit = false;
    try {
      await windowManager.setPreventClose(true);
    } catch (_) {}
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

  Future<void> _setTrayIcon(String path) {
    // 合并为目标路径：弱网/高负载时 setIcon 变慢，禁止无限排队导致「补帧狂抖」。
    _desiredIconPath = path;
    if (_iconBusy) return _iconChain;
    if (_lastIconPath == path) return _iconChain;

    _iconBusy = true;
    final target = path;
    _iconChain = _iconChain
        .catchError((_) {})
        .then((_) async {
          var next = _desiredIconPath ?? target;
          while (true) {
            if (_lastIconPath == next) break;
            try {
              await trayManager.setIcon(next);
              _lastIconPath = next;
            } catch (_) {
              break;
            }
            final latest = _desiredIconPath ?? next;
            if (latest == next) break;
            next = latest;
          }
        })
        .whenComplete(() {
          _iconBusy = false;
          final latest = _desiredIconPath;
          if (latest != null && latest != _lastIconPath) {
            unawaited(_setTrayIcon(latest));
          }
        });
    return _iconChain;
  }

  Future<void> _syncFlash() async {
    final hasAttention = _unread > 0 || _pendingAlert;
    final shouldFlashTray = _shouldFlashTray && hasAttention;
    if (shouldFlashTray) {
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
    // 放慢节奏；上一帧 setIcon 未完成则跳过，避免队列堆积后狂抖。
    _flashTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (_iconBusy) return;
      unawaited(_toggleFlashIcon());
    });
  }

  Future<void> _stopFlash() async {
    _flashTimer?.cancel();
    _flashTimer = null;
    _flashing = false;
    _flashVisible = true;
    await _setTrayIcon(_trayIcon);
  }

  Future<void> _toggleFlashIcon() async {
    if (!_flashing || _iconBusy) return;
    _flashVisible = !_flashVisible;
    await _setTrayIcon(_flashVisible ? _trayIcon : _trayIconBlank);
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
    _minimized = false;
    _focused = true;
    _pendingAlert = false;
    _queueSyncFlash();
    _emitInactiveChanged();
  }

  @override
  void onWindowMinimize() {
    _minimized = true;
    _emitInactiveChanged();
    // 最小化后若有未读，开始托盘闪烁提醒。
    _queueSyncFlash();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    _emitInactiveChanged();
    // 失焦不触发闪烁；若此前因最小化在闪，保持由 _shouldFlashTray 决定。
  }

  @override
  void onWindowFocus() {
    _focused = true;
    _minimized = false;
    if (!_hidden) {
      _pendingAlert = false;
    }
    _queueSyncFlash();
    _emitInactiveChanged();
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
