import Cocoa
import FlutterMacOS
import Sparkle

/// Flutter ↔ Sparkle：保留现有 API 弹窗公告，点击「立即更新」后走原生验签/替换/重启。
final class SparkleUpdaterBridge: NSObject, SPUUpdaterDelegate {
  static let shared = SparkleUpdaterBridge()

  private var updaterController: SPUStandardUpdaterController?
  private var channel: FlutterMethodChannel?

  func setup(with messenger: FlutterBinaryMessenger) {
    if updaterController == nil {
      let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
      )
      // 版本提示仍由 Flutter API 弹窗负责，避免 Sparkle 定时弹窗抢戏。
      controller.updater.automaticallyChecksForUpdates = false
      controller.updater.automaticallyDownloadsUpdates = false
      updaterController = controller
    }

    let methodChannel = FlutterMethodChannel(
      name: "nova.dunes/sparkle_updater",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "Sparkle bridge disposed",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "isSupported":
        result(true)
      case "checkForUpdates":
        DispatchQueue.main.async {
          guard let controller = self.updaterController else {
            result(
              FlutterError(
                code: "not_ready",
                message: "Sparkle updater not initialized",
                details: nil
              )
            )
            return
          }
          controller.checkForUpdates(nil)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }
}
