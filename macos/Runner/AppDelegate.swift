import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 关闭窗口不退出进程，交给 Flutter 侧隐藏到状态栏托盘（对齐 Windows）
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Dock 图标点击时若窗口已隐藏，重新前置窗口
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
