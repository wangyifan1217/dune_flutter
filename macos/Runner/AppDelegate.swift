import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var desktopWindowChannel: FlutterMethodChannel?

  /// 由 MainFlutterWindow 在引擎就绪后挂上，用于 Dock reopen → Flutter 恢复窗口。
  func setupDesktopWindowChannel(with messenger: FlutterBinaryMessenger) {
    desktopWindowChannel = FlutterMethodChannel(
      name: "nova.dunes/desktop_window",
      binaryMessenger: messenger
    )
  }

  // 关闭窗口不退出进程，交给 Flutter 侧隐藏到状态栏托盘（对齐 Windows）
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Dock 图标点击：窗口已隐藏时通知 Flutter 按托盘恢复路径重新显示
  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    // 不依赖 flag：状态栏等辅助窗口可能导致 hasVisibleWindows=true，
    // 从而跳过恢复；统一交给 Flutter _showFromTray。
    desktopWindowChannel?.invokeMethod("revealFromDock", arguments: nil)

    // 原生兜底（Flutter 尚未挂上 handler 时仍能前置窗口）
    let flutterWindows = sender.windows.filter {
      $0.contentViewController is FlutterViewController
    }
    let targets = flutterWindows.isEmpty ? sender.windows : flutterWindows
    for window in targets {
      window.makeKeyAndOrderFront(self)
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
