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

    // 只恢复主窗口。图片预览等 multi_window 子窗关闭后仍 hide 保活，
    // 若一并 makeKeyAndOrderFront，会出现「关了预览 → 退后台再开 → 预览又弹出」。
    let mainWindows = sender.windows.compactMap { $0 as? MainFlutterWindow }
    if !mainWindows.isEmpty {
      for window in mainWindows {
        window.makeKeyAndOrderFront(self)
      }
    } else {
      // 兜底：仅前置已可见窗口，避免把隐藏的预览子窗拉起来
      for window in sender.windows where window.isVisible {
        window.makeKeyAndOrderFront(self)
      }
    }
    sender.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
