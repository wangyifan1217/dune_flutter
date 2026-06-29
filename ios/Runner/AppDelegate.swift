import Flutter
import UIKit
import AVFoundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, XGPushDelegate {
  private let voiceChannelName = "dunes/audio_recorder"
  private var recorder: AVAudioRecorder?
  private var recordStartedAt: Date?
  private var outputPath: String?
  private var tpnsBridge: TpnsPushBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    TpnsPushBridge.launchOptions = launchOptions
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    tpnsBridge = TpnsPushBridge(
      application: UIApplication.shared,
      messenger: messenger,
      pushDelegate: self
    )
    tpnsBridge?.attach()

    let channel = FlutterMethodChannel(
      name: voiceChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "start":
        self.startRecord(result: result)
      case "stop":
        self.stopRecord(result: result, deleteFile: false)
      case "cancel":
        self.stopRecord(result: result, deleteFile: true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - XGPushDelegate

  func xgPushDidRegisteredDeviceToken(
    _ deviceToken: String?,
    xgToken: String?,
    error: Error?
  ) {
    tpnsBridge?.handleRegisteredToken(xgToken: xgToken, error: error)
  }

  func xgPushDidReceiveRemoteNotification(
    _ notification: Any,
    withCompletionHandler completionHandler: ((UInt) -> Void)? = nil
  ) {
    let userInfo = TpnsPushBridge.extractUserInfo(from: notification)
    let badge = TpnsPushBridge.parseBadgeCount(from: userInfo)
    if let badge = badge {
      tpnsBridge?.applyBadgeCount(badge)
    }
    tpnsBridge?.handleNotificationShown(badgeCount: badge)
    guard let completionHandler = completionHandler else { return }
    if #available(iOS 14.0, *) {
      completionHandler(
        UNNotificationPresentationOptions.banner.rawValue
          | UNNotificationPresentationOptions.sound.rawValue
          | UNNotificationPresentationOptions.badge.rawValue
      )
    } else {
      completionHandler(
        UNNotificationPresentationOptions.alert.rawValue
          | UNNotificationPresentationOptions.sound.rawValue
          | UNNotificationPresentationOptions.badge.rawValue
      )
    }
  }

  // MARK: - Voice recorder

  private func startRecord(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    let permission = session.recordPermission
    if permission == .undetermined {
      session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self = self else { return result(nil) }
          guard granted else {
            result(
              FlutterError(code: "AUDIO_PERMISSION_DENIED", message: "microphone denied", details: nil)
            )
            return
          }
          self.startRecordImpl(result: result)
        }
      }
      return
    }
    guard permission == .granted else {
      result(FlutterError(code: "AUDIO_PERMISSION_DENIED", message: "microphone denied", details: nil))
      return
    }
    startRecordImpl(result: result)
  }

  private func startRecordImpl(result: @escaping FlutterResult) {
    stopInternal(deleteFile: true)
    let path = "\(NSTemporaryDirectory())voice-\(Int(Date().timeIntervalSince1970 * 1000)).wav"
    let url = URL(fileURLWithPath: path)
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: 16000.0,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsNonInterleaved: false
    ]
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      let r = try AVAudioRecorder(url: url, settings: settings)
      r.prepareToRecord()
      r.record()
      recorder = r
      outputPath = path
      recordStartedAt = Date()
      result(true)
    } catch {
      stopInternal(deleteFile: true)
      result(FlutterError(code: "AUDIO_START_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func stopRecord(result: @escaping FlutterResult, deleteFile: Bool) {
    let durationMs = stopInternal(deleteFile: deleteFile)
    if deleteFile {
      result(nil)
      return
    }
    guard let path = outputPath, !path.isEmpty else {
      result(nil)
      return
    }
    result([
      "path": path,
      "durationMs": durationMs
    ])
  }

  @discardableResult
  private func stopInternal(deleteFile: Bool) -> Int {
    var durationMs = 0
    if let started = recordStartedAt {
      durationMs = max(0, Int(Date().timeIntervalSince(started) * 1000))
    }
    recorder?.stop()
    recorder = nil
    recordStartedAt = nil
    if deleteFile, let path = outputPath {
      try? FileManager.default.removeItem(atPath: path)
      outputPath = nil
    }
    return durationMs
  }
}

final class TpnsPushBridge {
  static let channelName = "dunes/tpns_push"
  static var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  private weak var application: UIApplication?
  private weak var pushDelegate: XGPushDelegate?
  private var channel: FlutterMethodChannel?
  private var accessId: UInt32 = 0
  private var accessKey = ""
  private var isStarted = false

  init(
    application: UIApplication,
    messenger: FlutterBinaryMessenger,
    pushDelegate: XGPushDelegate
  ) {
    self.application = application
    self.pushDelegate = pushDelegate
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
  }

  func attach() {
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func handleRegisteredToken(xgToken: String?, error: Error?) {
    if let error = error {
      NSLog("[DunesTpns] TPNS register failed: \(error.localizedDescription)")
      return
    }
    guard let token = xgToken, !token.isEmpty else { return }
    NSLog("[DunesTpns] TPNS register success")
    channel?.invokeMethod("onToken", arguments: token)
  }

  func handleNotificationShown(badgeCount: Int? = nil) {
    channel?.invokeMethod("onNotificationShown", arguments: badgeCount)
  }

  func applyBadgeCount(_ count: Int) {
    let n = max(0, count)
    DispatchQueue.main.async {
      UIApplication.shared.applicationIconBadgeNumber = n
      XGPush.defaultManager().setBadge(UInt32(n))
    }
  }

  static func extractUserInfo(from notification: Any) -> [AnyHashable: Any] {
    if #available(iOS 10.0, *), let un = notification as? UNNotification {
      return un.request.content.userInfo
    }
    if let dict = notification as? [AnyHashable: Any] {
      return dict
    }
    if let dict = notification as? NSDictionary {
      return dict as? [AnyHashable: Any] ?? [:]
    }
    return [:]
  }

  static func parseBadgeCount(from userInfo: [AnyHashable: Any]) -> Int? {
    if let aps = userInfo["aps"] as? [AnyHashable: Any] {
      if let badge = aps["badge"] as? Int, badge >= 0 {
        return badge
      }
      if let badge = aps["badge"] as? NSNumber, badge.intValue >= 0 {
        return badge.intValue
      }
    }
    for key in ["custom", "custom_content"] {
      if let raw = userInfo[key] as? String, let badge = parseBadgeJSON(raw) {
        return badge
      }
    }
    return nil
  }

  private static func parseBadgeJSON(_ raw: String) -> Int? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      let data = trimmed.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    if let badge = json["badgeCount"] as? Int, badge >= 0 {
      return badge
    }
    if let badge = json["badgeCount"] as? NSNumber, badge.intValue >= 0 {
      return badge.intValue
    }
    if let badge = json["badge"] as? Int, badge >= 0 {
      return badge
    }
    if let badge = json["badge"] as? NSNumber, badge.intValue >= 0 {
      return badge.intValue
    }
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      initPush(call, result: result)
    case "getToken":
      result(XGPushTokenManager.default().xgTokenString ?? "")
    case "bindAccount":
      bindAccount(call, result: result)
    case "unbindAccount":
      unbindAccount(call, result: result)
    case "setBadge":
      setBadge(call, result: result)
    case "requestAuthorization":
      requestAuthorization(result: result)
    case "isMiuiDevice":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initPush(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID", message: "missing args", details: nil))
      return
    }
    if let idStr = args["accessId"] as? String, let id = UInt32(idStr) {
      accessId = id
    }
    if let key = args["accessKey"] as? String {
      accessKey = key
    }
    if let cluster = args["clusterDomain"] as? String, !cluster.isEmpty {
      // configureClusterDomainName 在部分 TPNS 版本不存在，用 selector 动态调用以兼容
      let selector = NSSelectorFromString("configureClusterDomainName:")
      if XGPush.defaultManager().responds(to: selector) {
        XGPush.defaultManager().perform(selector, with: cluster)
      }
    }
    guard accessId > 0, !accessKey.isEmpty else {
      result(
        FlutterError(
          code: "NOT_CONFIGURED",
          message: "TPNS accessId/accessKey missing",
          details: nil
        )
      )
      return
    }
    if !isStarted {
      if let launchOptions = Self.launchOptions {
        XGPush.defaultManager().launchOptions = NSMutableDictionary(dictionary: launchOptions)
      }
      guard let delegate = pushDelegate else {
        result(FlutterError(code: "NO_DELEGATE", message: "missing push delegate", details: nil))
        return
      }
      XGPush.defaultManager().startXG(withAccessID: accessId, accessKey: accessKey, delegate: delegate)
      isStarted = true
      NSLog("[DunesTpns] TPNS startXG invoked accessId=\(accessId)")
    }
    result(true)
  }

  private func requestAuthorization(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
      granted,
      error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(code: "AUTH_FAILED", message: error.localizedDescription, details: nil)
          )
          return
        }
        if granted {
          self.application?.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  private func bindAccount(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID", message: "missing args", details: nil))
      return
    }
    let account = (args["account"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if account.isEmpty {
      result(FlutterError(code: "INVALID", message: "account is empty", details: nil))
      return
    }
    XGPushTokenManager.default().bind(withIdentifier: account, type: .account)
    result(true)
  }

  private func unbindAccount(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(true)
      return
    }
    let account = (args["account"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if account.isEmpty {
      result(true)
      return
    }
    XGPushTokenManager.default().unbind(withIdentifer: account, type: .account)
    result(true)
  }

  private func setBadge(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(true)
      return
    }
    let count = (args["count"] as? NSNumber)?.intValue ?? 0
    applyBadgeCount(count)
    result(true)
  }
}
