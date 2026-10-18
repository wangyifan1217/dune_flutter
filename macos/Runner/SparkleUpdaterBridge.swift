import Cocoa
import FlutterMacOS
import Sparkle

/// Flutter ↔ Sparkle。版本公告仍由 Flutter 弹窗负责；只有用户点「立即更新」才检查安装清单。
final class SparkleUpdaterBridge: NSObject, SPUUpdaterDelegate {
  static let shared = SparkleUpdaterBridge()

  private var updaterController: SPUStandardUpdaterController?
  private var channel: FlutterMethodChannel?
  private var updaterStarted = false
  private var startFailure: String?

  func setup(with messenger: FlutterBinaryMessenger) {
    if updaterController == nil {
      // 先清掉旧版本写进偏好的自动检查/自动安装，再启动。
      // 若先 startingUpdater，启动瞬间仍会读到旧偏好并开始一次后台安装，
      // 之后用户再点更新会被 Sparkle 当成「已有检查在进行」而直接忽略。
      let defaults = UserDefaults.standard
      defaults.set(false, forKey: "SUEnableAutomaticChecks")
      defaults.set(false, forKey: "SUAutomaticallyUpdate")

      let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
      )
      controller.updater.automaticallyChecksForUpdates = false
      controller.updater.automaticallyDownloadsUpdates = false
      do {
        try controller.updater.start()
        updaterStarted = true
      } catch {
        startFailure = error.localizedDescription
      }
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
        result(self.updaterStarted)
      case "checkForUpdates":
        DispatchQueue.main.async {
          self.beginUserCheck(result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }

  private func beginUserCheck(_ result: @escaping FlutterResult) {
    guard let updater = updaterController?.updater, updaterStarted else {
      result(
        FlutterError(
          code: "not_ready",
          message: startFailure ?? "更新程序尚未就绪，请完全退出沙丘后重新打开",
          details: nil
        )
      )
      return
    }
    guard updater.canCheckForUpdates else {
      let message = updater.sessionInProgress
        ? "已有一次更新检查在进行，请查看系统弹窗，或稍后再试"
        : "更新程序暂时不能检查更新，请完全退出沙丘后重新打开"
      result(FlutterError(code: "busy", message: message, details: nil))
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    // 后台检查：找到新版本才弹出 Sparkle 安装窗；没找到或失败只回调 Flutter，避免点了没窗口。
    updater.checkForUpdatesInBackground()
    result(nil)
  }

  private func notify(_ method: String, arguments: Any? = nil) {
    channel?.invokeMethod(method, arguments: arguments)
  }

  /// 即将写入新版本前再通知 Flutter 松绑（与 Dart 侧预松绑双保险）。
  func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
    notify("prepareForQuit")
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    notify("prepareForQuit")
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    notify("updateFound")
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
    notify("updateNotFound")
    notify("rearmPreventClose")
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    notify("updateFailed", arguments: ["message": error.localizedDescription])
    notify("rearmPreventClose")
  }
}
