/// Windows 桌面托盘：关闭进托盘、未读闪烁（微信 PC 风格）。
/// 非 Windows 平台为空实现。
library;

import 'windows_desktop_tray_stub.dart'
    if (dart.library.io) 'windows_desktop_tray_io.dart'
    as impl;

Future<void> initWindowsDesktopTray() => impl.initWindowsDesktopTray();

void windowsTrayUpdateUnread(int total) => impl.windowsTrayUpdateUnread(total);

void windowsTrayNotifyIncomingMessage() =>
    impl.windowsTrayNotifyIncomingMessage();

/// 当前桌面窗口是否最小化、失焦或已隐藏到托盘。
bool windowsTrayIsWindowInactive() => impl.windowsTrayIsWindowInactive();

/// 窗口前后台状态变化（最小化 / 失焦 / 托盘隐藏 ↔ 恢复）。
void setWindowsTrayOnInactiveChanged(void Function(bool inactive)? callback) =>
    impl.setWindowsTrayOnInactiveChanged(callback);

/// 从托盘/通知点击恢复窗口。
void windowsTrayReveal() => impl.windowsTrayReveal();

/// 托盘「退出」前回调（用于清除登录会话）。
void setWindowsTrayOnBeforeQuit(Future<void> Function()? callback) =>
    impl.setWindowsTrayOnBeforeQuit(callback);

/// 应用更新前解除关窗进托盘拦截；[exitProcess] 为 true 时立刻退出进程。
Future<void> windowsTrayPrepareQuitForAppUpdate({bool exitProcess = false}) =>
    impl.windowsTrayPrepareQuitForAppUpdate(exitProcess: exitProcess);

/// Sparkle 未安装时恢复托盘防关闭。
Future<void> windowsTrayRearmPreventCloseAfterUpdateCancelled() =>
    impl.windowsTrayRearmPreventCloseAfterUpdateCancelled();
