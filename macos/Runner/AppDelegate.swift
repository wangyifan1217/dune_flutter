import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var desktopWindowChannel: FlutterMethodChannel?
  private var desktopFileDragChannel: FlutterMethodChannel?
  private static let iconRefreshVersionDefaultsKey = "dunes.last_icon_refresh_version"

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    refreshBundleIconCacheIfVersionChanged()
  }

  /// 覆盖升级（Sparkle 或 DMG 拖装）后，macOS 的 LaunchServices 与 Dock 常缓存旧图标。
  /// 仅在版本号变化后的首次启动执行一次：更新 Bundle mtime、重注册 LaunchServices 并刷新 Dock。
  private func refreshBundleIconCacheIfVersionChanged() {
    let info = Bundle.main.infoDictionary
    let shortVersion = (info?["CFBundleShortVersionString"] as? String) ?? ""
    let buildNumber = (info?["CFBundleVersion"] as? String) ?? ""
    let currentKey = "\(shortVersion)+\(buildNumber)"
    guard !currentKey.isEmpty, currentKey != "+" else { return }

    let defaults = UserDefaults.standard
    let lastKey = defaults.string(forKey: Self.iconRefreshVersionDefaultsKey)
    guard lastKey != currentKey else { return }
    defaults.set(currentKey, forKey: Self.iconRefreshVersionDefaultsKey)

    if let freshIcon = NSImage(named: NSImage.applicationIconName) {
      NSApp.applicationIconImage = freshIcon
    }

    let bundlePath = Bundle.main.bundlePath
    guard bundlePath.hasSuffix(".app") else { return }

    DispatchQueue.global(qos: .utility).async {
      try? FileManager.default.setAttributes(
        [.modificationDate: Date()],
        ofItemAtPath: bundlePath
      )
      DispatchQueue.main.async {
        NSWorkspace.shared.setIcon(nil, forFile: bundlePath, options: [])
        NSWorkspace.shared.noteFileSystemChanged(bundlePath)
      }

      let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
      if FileManager.default.isExecutableFile(atPath: lsregisterPath) {
        let regProc = Process()
        regProc.executableURL = URL(fileURLWithPath: lsregisterPath)
        regProc.arguments = ["-f", bundlePath]
        try? regProc.run()
        regProc.waitUntilExit()
      }

      // 刷新固定在 Dock 上的旧图标缓存（仅在版本升级后的首次启动执行一次）。
      let killallPath = "/usr/bin/killall"
      if FileManager.default.isExecutableFile(atPath: killallPath) {
        let dockProc = Process()
        dockProc.executableURL = URL(fileURLWithPath: killallPath)
        dockProc.arguments = ["Dock"]
        try? dockProc.run()
        dockProc.waitUntilExit()
      }
    }
  }

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

  func notifyDesktopWindow(method: String, arguments: Any?) {
    desktopWindowChannel?.invokeMethod(method, arguments: arguments)
  }

  override func applicationDidHide(_ notification: Notification) {
    super.applicationDidHide(notification)
    notifyDesktopWindow(method: "appHiddenChanged", arguments: ["hidden": true])
  }

  override func applicationDidUnhide(_ notification: Notification) {
    super.applicationDidUnhide(notification)
    notifyDesktopWindow(method: "appHiddenChanged", arguments: ["hidden": false])
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

  func setupDesktopFileDragChannel(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "nova.dunes/desktop_file_drag",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "start" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let paths = ((call.arguments as? [String: Any])?["paths"] as? [String]) ?? []
      // 必须同步开始：异步会丢掉当前鼠标拖动手势，Finder 收不到文件。
      let ok = DesktopFileDragSource.shared.begin(paths: paths)
      if ok {
        result(nil)
      } else {
        result(
          FlutterError(
            code: "no_file",
            message: "没有可拖出的本地文件",
            details: nil
          )
        )
      }
    }
    desktopFileDragChannel = channel
  }
}

/// 把本地文件拖到 Finder / 桌面（复制，不移动应用缓存）。
final class DesktopFileDragSource: NSObject, NSDraggingSource {
  static let shared = DesktopFileDragSource()

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return .copy
  }

  func begin(paths: [String]) -> Bool {
    let urls = paths
      .map { URL(fileURLWithPath: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !urls.isEmpty else { return false }
    guard let event = NSApp.currentEvent else { return false }
    guard event.type == .leftMouseDown || event.type == .leftMouseDragged else {
      return false
    }
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
    guard let view = window.contentView else { return false }
    let loc = view.convert(event.locationInWindow, from: nil)
    let items: [NSDraggingItem] = urls.map { url in
      let item = NSDraggingItem(pasteboardWriter: url as NSURL)
      let icon = NSWorkspace.shared.icon(forFile: url.path)
      icon.size = NSSize(width: 32, height: 32)
      item.setDraggingFrame(
        NSRect(x: loc.x - 16, y: loc.y - 16, width: 32, height: 32),
        contents: icon
      )
      return item
    }
    view.beginDraggingSession(with: items, event: event, source: self)
    return true
  }
}
