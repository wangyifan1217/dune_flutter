import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private var titleObservers: [NSKeyValueObservation] = []
  private var visibilityObservers: [NSObjectProtocol] = []

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 与 Windows 桌面端对齐：默认 1080×720，最小 1024×680（高于双栏断点，避免缩成 APP 布局）
    self.setContentSize(NSSize(width: 1080, height: 720))
    self.minSize = NSSize(width: 1024, height: 680)
    self.center()
    applySingleTitle("沙丘")
    observeTitleDuplication()

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      MainFlutterWindow.pauseEngineWhenWindowOccluded(controller)
    }
    let messenger = flutterViewController.engine.binaryMessenger
    SparkleUpdaterBridge.shared.setup(with: messenger)
    TrayPeekController.shared.setup(with: messenger)
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
      appDelegate.setupDesktopWindowChannel(with: messenger)
      appDelegate.setupDesktopFileDragChannel(with: messenger)
    }
    observeMainWindowVisibility(engine: flutterViewController.engine)

    super.awakeFromNib()
  }

  deinit {
    for token in visibilityObservers {
      NotificationCenter.default.removeObserver(token)
    }
  }

  /// 切 Space / Cmd+H / 被挡住时停主引擎排帧，并告诉 Dart 冻 Ticker。
  private func observeMainWindowVisibility(engine: FlutterEngine) {
    let token = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification,
      object: self,
      queue: .main
    ) { [weak self] notification in
      engine.handleDidChangeOcclusionState(notification)
      guard let self else { return }
      let visible = self.occlusionState.contains(.visible)
      if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
        appDelegate.notifyDesktopWindow(
          method: "occlusionChanged",
          arguments: ["visible": visible]
        )
      }
    }
    visibilityObservers.append(token)
  }

  /// 图片预览等 multi_window 子引擎收不到系统 occlusion，自己补一刀停帧。
  static func pauseEngineWhenWindowOccluded(_ controller: FlutterViewController) {
    DispatchQueue.main.async { [weak controller] in
      guard let controller, let window = controller.view.window else { return }
      NotificationCenter.default.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification,
        object: window,
        queue: .main
      ) { [weak controller] notification in
        controller?.engine.handleDidChangeOcclusionState(notification)
      }
      controller.engine.handleDidChangeOcclusionState(
        Notification(
          name: NSWindow.didChangeOcclusionStateNotification,
          object: window
        )
      )
    }
  }

  /// macOS 11+ 会把 title / subtitle 叠成两行；Tahoe 上 dual-set 后常见两个「沙丘」。
  private func applySingleTitle(_ text: String) {
    title = text
    stripDuplicateSubtitle()
  }

  private func stripDuplicateSubtitle() {
    guard #available(macOS 11.0, *) else { return }
    if !subtitle.isEmpty {
      subtitle = ""
    }
  }

  private func observeTitleDuplication() {
    titleObservers.append(observe(\.title, options: [.new]) { [weak self] _, _ in
      self?.stripDuplicateSubtitle()
    })
    if #available(macOS 11.0, *) {
      titleObservers.append(observe(\.subtitle, options: [.new]) { [weak self] _, change in
        guard let self, let value = change.newValue, !value.isEmpty else { return }
        self.subtitle = ""
      })
    }
  }
}
