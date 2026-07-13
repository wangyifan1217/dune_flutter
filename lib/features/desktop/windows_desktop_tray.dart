/// Windows 桌面托盘：关闭进托盘、未读闪烁（微信 PC 风格）。
/// 非 Windows 平台为空实现。
library;

import 'windows_desktop_tray_stub.dart'
    if (dart.library.io) 'windows_desktop_tray_io.dart' as impl;

Future<void> initWindowsDesktopTray() => impl.initWindowsDesktopTray();

void windowsTrayUpdateUnread(int total) => impl.windowsTrayUpdateUnread(total);

void windowsTrayNotifyIncomingMessage() =>
    impl.windowsTrayNotifyIncomingMessage();
