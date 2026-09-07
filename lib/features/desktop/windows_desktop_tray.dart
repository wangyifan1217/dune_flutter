/// Windows 桌面托盘：关闭进托盘、未读闪烁（微信 PC 风格）。
/// 非 Windows 平台为空实现。
library;

import 'package:flutter/foundation.dart';

import 'windows_desktop_tray_stub.dart'
    if (dart.library.io) 'windows_desktop_tray_io.dart'
    as impl;
import 'windows_tray_unread_item.dart';

export 'windows_tray_unread_item.dart';

Future<void> initWindowsDesktopTray() => impl.initWindowsDesktopTray();

void windowsTrayUpdateUnread(int total) => impl.windowsTrayUpdateUnread(total);

void windowsTrayUpdateUnreadItems(List<WindowsTrayUnreadItem> items) =>
    impl.windowsTrayUpdateUnreadItems(items);

/// 点击托盘未读浮层中的会话。`conversationId == 0` 只打开主窗口。
void setWindowsTrayOnPeekOpen(void Function(int conversationId)? callback) =>
    impl.setWindowsTrayOnPeekOpen(callback);

/// 无未读时托盘系统 tooltip 显示「沙丘: 姓名」。
void windowsTraySetUserLabel(String name) => impl.windowsTraySetUserLabel(name);

void windowsTrayNotifyIncomingMessage() =>
    impl.windowsTrayNotifyIncomingMessage();

/// 当前桌面窗口是否最小化、失焦或已隐藏到托盘。
bool windowsTrayIsWindowInactive() => impl.windowsTrayIsWindowInactive();

/// 窗口已隐藏到托盘或最小化（不含失焦）。看不见时才能冻动画。
bool windowsTrayIsWindowObscured() => impl.windowsTrayIsWindowObscured();

/// [windowsTrayIsWindowObscured] 的可监听版本，供根节点 TickerMode 使用。
ValueListenable<bool> windowsTrayWindowObscuredListenable() =>
    impl.windowsTrayWindowObscuredListenable();

/// 窗口前后台状态变化（最小化 / 失焦 / 托盘隐藏 ↔ 恢复）。
void setWindowsTrayOnInactiveChanged(void Function(bool inactive)? callback) =>
    impl.setWindowsTrayOnInactiveChanged(callback);

/// 从托盘/通知点击恢复窗口。
void windowsTrayReveal() => impl.windowsTrayReveal();

/// 最小化到任务栏（Esc）；与点关闭进托盘不同。
Future<void> windowsTrayMinimize() => impl.windowsTrayMinimize();

/// 托盘「退出」前回调（用于清除登录会话）。
void setWindowsTrayOnBeforeQuit(Future<void> Function()? callback) =>
    impl.setWindowsTrayOnBeforeQuit(callback);

/// 应用更新前解除关窗进托盘拦截；[exitProcess] 为 true 时立刻退出进程。
Future<void> windowsTrayPrepareQuitForAppUpdate({bool exitProcess = false}) =>
    impl.windowsTrayPrepareQuitForAppUpdate(exitProcess: exitProcess);

/// Sparkle 未安装时恢复托盘防关闭。
Future<void> windowsTrayRearmPreventCloseAfterUpdateCancelled() =>
    impl.windowsTrayRearmPreventCloseAfterUpdateCancelled();
