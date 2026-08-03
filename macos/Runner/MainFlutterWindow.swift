import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 与 Windows 桌面端对齐：默认 1080×720，最小 1024×680（高于双栏断点，避免缩成 APP 布局）
    self.setContentSize(NSSize(width: 1080, height: 720))
    self.minSize = NSSize(width: 1024, height: 680)
    self.center()
    self.title = "沙丘"

    RegisterGeneratedPlugins(registry: flutterViewController)
    SparkleUpdaterBridge.shared.setup(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
