import Flutter
import UIKit
import AVFoundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, XGPushDelegate,
  FlutterStreamHandler
{
  private let voiceChannelName = "dunes/audio_recorder"
  private let voiceStreamChannelName = "dunes/audio_recorder_stream"
  private var audioEngine: AVAudioEngine?
  private var pcmFileHandle: FileHandle?
  private var pcmPath: String?
  private var recordStartedAt: Date?
  private var activeSegmentStartedAt: Date?
  private var accumulatedDurationMs: Int = 0
  private var outputPath: String?
  private var isRecording = false
  private var isPaused = false
  private var streamSink: FlutterEventSink?
  private let streamLock = NSLock()
  private var tpnsBridge: TpnsPushBridge?
  private var audioConverter: AVAudioConverter?
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16000,
    channels: 1,
    interleaved: true
  )!

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
      case "pause":
        self.pauseRecord(result: result)
      case "resume":
        self.resumeRecord(result: result)
      case "stop":
        self.stopRecord(result: result, deleteFile: false)
      case "cancel":
        self.stopRecord(result: result, deleteFile: true)
      case "status":
        result([
          "isRecording": self.isRecording,
          "isPaused": self.isPaused,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let streamChannel = FlutterEventChannel(
      name: voiceStreamChannelName,
      binaryMessenger: messenger
    )
    streamChannel.setStreamHandler(self)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil
    )
  }

  // MARK: - Audio interruption recovery

  @objc private func handleAudioInterruption(_ note: Notification) {
    guard isRecording,
      let info = note.userInfo,
      let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
    else {
      return
    }
    switch type {
    case .began:
      // 系统已暂停音频输入（来电/Siri/闹钟等），保持状态，等待中断结束后恢复。
      audioEngine?.pause()
    case .ended:
      var shouldResume = true
      if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
        shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw)
          .contains(.shouldResume)
      }
      if shouldResume {
        resumeEngineAfterInterruption()
      }
    @unknown default:
      break
    }
  }

  @objc private func handleMediaServicesReset(_ note: Notification) {
    // 媒体服务被重置后，音频引擎会失效，需要重新激活会话并启动引擎。
    resumeEngineAfterInterruption()
  }

  private func resumeEngineAfterInterruption() {
    guard isRecording, !isPaused else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      if let engine = audioEngine, !engine.isRunning {
        try engine.start()
      }
    } catch {
      // best-effort：无法恢复时保持已录部分，stop 时按已有数据处理。
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
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let pcm = "\(NSTemporaryDirectory())voice-\(stamp).pcm"
    let wav = "\(NSTemporaryDirectory())voice-\(stamp).wav"
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .spokenAudio,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
      )
      try session.setPreferredSampleRate(16000)
      try session.setActive(true)

      FileManager.default.createFile(atPath: pcm, contents: nil)
      streamLock.lock()
      pcmFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: pcm))
      streamLock.unlock()
      pcmPath = pcm
      outputPath = wav

      let engine = AVAudioEngine()
      let input = engine.inputNode
      let format = input.inputFormat(forBus: 0)
      // 麦克风硬件通常是 44.1k/48k 浮点，需重采样为 16k 单声道 Int16，
      // 否则 ASR 按 16k 解析高采样率音频会变速、识别率极低。
      audioConverter = AVAudioConverter(from: format, to: targetFormat)
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
        self?.consumeAudioBuffer(buffer)
      }
      try engine.start()
      audioEngine = engine

      recordStartedAt = Date()
      activeSegmentStartedAt = Date()
      accumulatedDurationMs = 0
      isRecording = true
      isPaused = false
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

  private func pauseRecord(result: @escaping FlutterResult) {
    guard isRecording, !isPaused else {
      result(false)
      return
    }
    accumulatedDurationMs += currentSegmentDurationMs()
    activeSegmentStartedAt = nil
    isPaused = true
    audioEngine?.pause()
    result(true)
  }

  private func resumeRecord(result: @escaping FlutterResult) {
    guard isRecording, isPaused else {
      result(false)
      return
    }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      if let engine = audioEngine {
        if !engine.isRunning {
          try engine.start()
        }
      } else {
        throw NSError(
          domain: "dunes.audio",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "audio engine unavailable"]
        )
      }
      isPaused = false
      activeSegmentStartedAt = Date()
      result(true)
    } catch {
      result(
        FlutterError(
          code: "AUDIO_RESUME_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func currentSegmentDurationMs() -> Int {
    guard isRecording, !isPaused, let started = activeSegmentStartedAt else {
      return 0
    }
    return max(0, Int(Date().timeIntervalSince(started) * 1000))
  }

  private func currentDurationMs() -> Int {
    return max(0, accumulatedDurationMs + currentSegmentDurationMs())
  }

  @discardableResult
  private func stopInternal(deleteFile: Bool) -> Int {
    let durationMs = currentDurationMs()
    isRecording = false
    isPaused = false
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    audioEngine = nil
    audioConverter = nil
    streamLock.lock()
    let handle = pcmFileHandle
    pcmFileHandle = nil
    streamLock.unlock()
    try? handle?.close()
    recordStartedAt = nil
    activeSegmentStartedAt = nil
    accumulatedDurationMs = 0

    let localPcmPath = pcmPath
    pcmPath = nil

    if deleteFile, let path = outputPath {
      if let localPcmPath {
        try? FileManager.default.removeItem(atPath: localPcmPath)
      }
      try? FileManager.default.removeItem(atPath: path)
      outputPath = nil
      return durationMs
    }

    if let localPcmPath, let localWavPath = outputPath {
      do {
        try writeWavFromPcm(pcmPath: localPcmPath, wavPath: localWavPath)
        try? FileManager.default.removeItem(atPath: localPcmPath)
      } catch {
        try? FileManager.default.removeItem(atPath: localPcmPath)
        try? FileManager.default.removeItem(atPath: localWavPath)
        outputPath = nil
      }
    }
    return durationMs
  }

  private func consumeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard isRecording, !isPaused else { return }
    let resampled: Data?
    if let converter = audioConverter {
      resampled = convertToTargetData(buffer: buffer, converter: converter)
    } else {
      resampled = pcmData(from: buffer)
    }
    guard let data = resampled, !data.isEmpty else { return }
    streamLock.lock()
    let handle = pcmFileHandle
    let sink = streamSink
    streamLock.unlock()

    do {
      try handle?.write(contentsOf: data)
    } catch {
      // Keep streaming best-effort; stop() will clean up.
    }
    if let sink {
      DispatchQueue.main.async {
        sink(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private func convertToTargetData(
    buffer: AVAudioPCMBuffer,
    converter: AVAudioConverter
  ) -> Data? {
    let ratio = targetFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard capacity > 0,
      let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
    else {
      return nil
    }
    var fed = false
    var convError: NSError?
    let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
      if fed {
        outStatus.pointee = .noDataNow
        return nil
      }
      fed = true
      outStatus.pointee = .haveData
      return buffer
    }
    if status == .error || convError != nil {
      return nil
    }
    let frames = Int(outBuffer.frameLength)
    guard frames > 0, let channel = outBuffer.int16ChannelData else { return nil }
    return Data(bytes: channel[0], count: frames * MemoryLayout<Int16>.size)
  }

  private func pcmData(from buffer: AVAudioPCMBuffer) -> Data? {
    let frames = Int(buffer.frameLength)
    guard frames > 0 else { return nil }
    let channels = Int(buffer.format.channelCount)

    if let int16 = buffer.int16ChannelData {
      var data = Data(capacity: frames * 2)
      for i in 0..<frames {
        let sample: Int32
        if channels > 1 {
          sample = (Int32(int16[0][i]) + Int32(int16[1][i])) / 2
        } else {
          sample = Int32(int16[0][i])
        }
        var s = Int16(max(Int32(Int16.min), min(Int32(Int16.max), sample)))
        data.append(Data(bytes: &s, count: MemoryLayout<Int16>.size))
      }
      return data
    }

    if let floats = buffer.floatChannelData {
      var data = Data(capacity: frames * 2)
      for i in 0..<frames {
        let mono: Float
        if channels > 1 {
          mono = (floats[0][i] + floats[1][i]) * 0.5
        } else {
          mono = floats[0][i]
        }
        let clamped = max(-1.0, min(1.0, mono))
        var s = Int16(clamped * Float(Int16.max))
        data.append(Data(bytes: &s, count: MemoryLayout<Int16>.size))
      }
      return data
    }
    return nil
  }

  private func writeWavFromPcm(pcmPath: String, wavPath: String) throws {
    let pcmData = try Data(contentsOf: URL(fileURLWithPath: pcmPath))
    var wav = Data()
    wav.append(wavHeader(dataLength: pcmData.count))
    wav.append(pcmData)
    try wav.write(to: URL(fileURLWithPath: wavPath), options: .atomic)
  }

  private func wavHeader(dataLength: Int) -> Data {
    let sampleRate: UInt32 = 16_000
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = channels * (bitsPerSample / 8)
    let riffSize: UInt32 = 36 + UInt32(dataLength)

    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(riffSize.leData)
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    data.append(UInt32(16).leData)
    data.append(UInt16(1).leData)
    data.append(channels.leData)
    data.append(sampleRate.leData)
    data.append(byteRate.leData)
    data.append(blockAlign.leData)
    data.append(bitsPerSample.leData)
    data.append("data".data(using: .ascii)!)
    data.append(UInt32(dataLength).leData)
    return data
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
  {
    streamLock.lock()
    streamSink = events
    streamLock.unlock()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    streamLock.lock()
    streamSink = nil
    streamLock.unlock()
    return nil
  }
}

private extension FixedWidthInteger {
  var leData: Data {
    var v = self.littleEndian
    return Data(bytes: &v, count: MemoryLayout<Self>.size)
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
      XGPush.defaultManager().setBadge(n)
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
