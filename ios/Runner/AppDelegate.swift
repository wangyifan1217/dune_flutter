import Flutter
import UIKit
import AVFoundation
import CallKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, XGPushDelegate,
  FlutterStreamHandler, CXCallObserverDelegate
{
  // FlutterAppDelegate 已实现 UNUserNotificationCenterDelegate，勿再重复声明。
  private let voiceChannelName = "dunes/audio_recorder"
  private let voiceStreamChannelName = "dunes/audio_recorder_stream"
  private let voiceEventsChannelName = "dunes/audio_recorder_events"
  private let meetingAudioChannelName = "dunes/meeting_audio"
  private var audioEngine: AVAudioEngine?
  private var m4aWriter: StreamingAacM4aWriter?
  private var recordStartedAt: Date?
  private var activeSegmentStartedAt: Date?
  private var accumulatedDurationMs: Int = 0
  private var outputPath: String?
  private var segmentPaths: [String] = []
  private var pendingMergeSegmentPaths: [String] = []
  private var needsCaptureRebuild = false
  private var isRecording = false
  private var isPaused = false
  /// 来电/系统抢麦导致的暂停才允许自动续录；用户点暂停、耳机拔出不自动续。
  private var pausedBySystemInterruption = false
  private let callObserver = CXCallObserver()
  private var sessionTracking = false
  private var sessionTitle = ""
  private var rotateTimer: Timer?
  private var crashWav: CrashSafeWavWriter?
  /// 忽略自身 setCategory / defaultToSpeaker 触发的路由回调，避免误报「被其他软件占用」。
  private var ignoreRouteChangeUntil: Date?
  private var streamSink: FlutterEventSink?
  private let streamLock = NSLock()
  private var recorderEventSink: FlutterEventSink?
  private let recorderEventLock = NSLock()
  private let recorderEventHandler = AudioRecorderEventHandler()
  private var tauVoiceCallAudio: TauVoiceCallAudio?
  private var tauVoiceCallCallKit: TauVoiceCallCallKit?
  private var tpnsBridge: TpnsPushBridge?
  private var pendingTpnsNotificationClick: [AnyHashable: Any]?
  private var meetingAudioPicker: MeetingAudioFilePicker?
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

  override func applicationWillTerminate(_ application: UIApplication) {
    flushLiveSessionForDeath()
    super.applicationWillTerminate(application)
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
    tauVoiceCallAudio = TauVoiceCallAudio(messenger: messenger)
    tauVoiceCallCallKit = TauVoiceCallCallKit(messenger: messenger)
    if let pending = pendingTpnsNotificationClick {
      tpnsBridge?.handleNotificationClicked(userInfo: pending)
      pendingTpnsNotificationClick = nil
    }

    let channel = FlutterMethodChannel(
      name: voiceChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "start":
        self.startRecord(call: call, result: result)
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
      case "abandonedSession":
        result(self.abandonedSessionPayload())
      case "recoverAbandonedSession":
        self.recoverAbandonedSession(result: result)
      case "discardAbandonedSession":
        self.discardAbandonedSession()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let streamChannel = FlutterEventChannel(
      name: voiceStreamChannelName,
      binaryMessenger: messenger
    )
    streamChannel.setStreamHandler(self)

    recorderEventHandler.owner = self
    let eventsChannel = FlutterEventChannel(
      name: voiceEventsChannelName,
      binaryMessenger: messenger
    )
    eventsChannel.setStreamHandler(recorderEventHandler)
    callObserver.setDelegate(self, queue: .main)

    let meetingAudioChannel = FlutterMethodChannel(
      name: meetingAudioChannelName,
      binaryMessenger: messenger
    )
    meetingAudioChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
      case "pickAudioFile":
        if self.meetingAudioPicker == nil {
          self.meetingAudioPicker = MeetingAudioFilePicker()
        }
        self.meetingAudioPicker?.pick(result: result)
      case "convertWavToM4a":
        guard let args = call.arguments as? [String: Any],
          let inputPath = args["inputPath"] as? String,
          let outputPath = args["outputPath"] as? String
        else {
          result(
            FlutterError(
              code: "INVALID_ARGS",
              message: "inputPath/outputPath required",
              details: nil
            ))
          return
        }
        self.convertWavToM4a(inputPath: inputPath, outputPath: outputPath, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidEnterBackground(_:)),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillEnterForeground(_:)),
      name: UIApplication.willEnterForegroundNotification,
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
      autoPauseForInterruption(reason: "interruption", allowAutoResume: true)
    case .ended:
      guard isRecording else { return }
      let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
      if options.contains(.shouldResume) || optionsRaw == 0 {
        tryNativeResumeAfterSystemInterruption()
      } else {
        emitRecorderEvent(["kind": "interruptionEnded"])
      }
    @unknown default:
      break
    }
  }

  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    let hasActiveCall = callObserver.calls.contains { !$0.hasEnded }
    if !hasActiveCall {
      tryNativeResumeAfterSystemInterruption()
    }
  }

  /// 来电等系统音频中断：立即落盘当前片段并暂停，避免 stop 时录音丢失。
  private func autoPauseForInterruption(reason: String, allowAutoResume: Bool = true) {
    guard isRecording else { return }
    if !isPaused {
      accumulatedDurationMs += currentSegmentDurationMs()
      activeSegmentStartedAt = nil
      isPaused = true
      pausedBySystemInterruption = allowAutoResume
      emitRecorderEvent(["kind": "paused", "reason": reason])
      if allowAutoResume {
        postRecordingPausedNotification()
      }
    } else if allowAutoResume {
      pausedBySystemInterruption = true
    }
    needsCaptureRebuild = true
    finalizeCurrentSegmentIfNeeded()
    teardownAudioEngine()
    crashWav?.flushHeader()
    persistLiveSession()
  }

  /// 挂断/系统归还麦克风后，尽量在原生层直接续录（不依赖 Flutter 是否还活着）。
  private func tryNativeResumeAfterSystemInterruption() {
    guard isRecording, isPaused, pausedBySystemInterruption else { return }
    do {
      try resumeCaptureAfterPause()
      pausedBySystemInterruption = false
      clearRecordingPausedNotification()
      emitRecorderEvent(["kind": "resumed", "reason": "system"])
    } catch {
      emitRecorderEvent(["kind": "interruptionEnded"])
    }
  }

  private func resumeCaptureAfterPause() throws {
    try prepareAudioSessionForRecording()
    if m4aWriter == nil {
      try startNewSegmentWriter()
    }
    if needsCaptureRebuild || audioEngine == nil {
      teardownAudioEngine()
      try setupAudioEngine()
      needsCaptureRebuild = false
    } else if let engine = audioEngine, !engine.isRunning {
      try engine.start()
    }
    isPaused = false
    activeSegmentStartedAt = Date()
  }

  private func postRecordingPausedNotification() {
    let content = UNMutableNotificationContent()
    content.title = "会议录音已暂停"
    content.body = "来电结束后将自动继续，已录部分已保存"
    content.sound = nil
    let request = UNNotificationRequest(
      identifier: "dunes.meeting.recording.paused",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
  }

  private func clearRecordingPausedNotification() {
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: ["dunes.meeting.recording.paused"]
    )
  }

  private func liveSessionURL() -> URL {
    URL(fileURLWithPath: voiceRecordingDirectory())
      .appendingPathComponent("live_session.json")
  }

  private func livePcmURL() -> URL {
    URL(fileURLWithPath: voiceRecordingDirectory()).appendingPathComponent("live_pcm.wav")
  }

  private func persistLiveSession() {
    guard sessionTracking else { return }
    var segs = segmentPaths.filter { FileManager.default.fileExists(atPath: $0) }
    if let current = outputPath,
      FileManager.default.fileExists(atPath: current),
      !segs.contains(current)
    {
      segs.append(current)
    }
    crashWav?.flushHeader()
    let pcmPath = livePcmURL().path
    let pcmExists = (try? FileManager.default.attributesOfItem(atPath: pcmPath)[.size] as? NSNumber)?
      .intValue ?? 0 > 44
    let payload: [String: Any] = [
      "title": sessionTitle,
      "startedAtMs": Int((recordStartedAt ?? Date()).timeIntervalSince1970 * 1000),
      "durationMs": pcmExists
        ? CrashSafeWavWriter.durationMs(path: pcmPath) : currentDurationMs(),
      "segments": segs,
      "pcmPath": pcmPath,
    ]
    guard JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(withJSONObject: payload)
    else { return }
    try? data.write(to: liveSessionURL(), options: .atomic)
  }

  private func clearLiveSessionFile() {
    try? FileManager.default.removeItem(at: liveSessionURL())
  }

  private func startSegmentRotateTimer() {
    rotateTimer?.invalidate()
    guard sessionTracking else { return }
    rotateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      self?.rotateLiveSegmentIfNeeded()
    }
  }

  private func rotateLiveSegmentIfNeeded() {
    guard isRecording, !isPaused, sessionTracking else { return }
    accumulatedDurationMs += currentSegmentDurationMs()
    activeSegmentStartedAt = Date()
    finalizeCurrentSegmentIfNeeded()
    try? startNewSegmentWriter()
    persistLiveSession()
  }

  private func flushLiveSessionForDeath() {
    guard isRecording, sessionTracking else { return }
    if !isPaused {
      accumulatedDurationMs += currentSegmentDurationMs()
      activeSegmentStartedAt = nil
      isPaused = true
    }
    finalizeCurrentSegmentIfNeeded()
    teardownAudioEngine()
    crashWav?.flushHeader()
    persistLiveSession()
  }

  private func readAbandonedSession() -> [String: Any]? {
    if isRecording && sessionTracking { return nil }
    if let data = try? Data(contentsOf: liveSessionURL()),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      return json
    }
    let pcmPath = livePcmURL().path
    let size = (try? FileManager.default.attributesOfItem(atPath: pcmPath)[.size] as? NSNumber)?
      .intValue ?? 0
    guard size > 44 + 1024 else { return nil }
    return [
      "title": "",
      "durationMs": CrashSafeWavWriter.durationMs(path: pcmPath),
      "segments": [String](),
      "pcmPath": pcmPath,
    ]
  }

  private func abandonedPcmPath(_ json: [String: Any]) -> String? {
    let path = (json["pcmPath"] as? String) ?? ""
    guard !path.isEmpty else { return nil }
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
      .intValue ?? 0
    return size > 44 + 1024 ? path : nil
  }

  private func abandonedSessionPayload() -> [String: Any]? {
    guard let json = readAbandonedSession() else { return nil }
    let pcm = abandonedPcmPath(json)
    let segs = ((json["segments"] as? [String]) ?? []).filter { path in
      let attrs = try? FileManager.default.attributesOfItem(atPath: path)
      let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
      return size > 1024
    }
    if pcm == nil && segs.isEmpty { return nil }
    let durationMs: Int
    if let pcm {
      durationMs = CrashSafeWavWriter.durationMs(path: pcm)
    } else {
      durationMs = (json["durationMs"] as? NSNumber)?.intValue
        ?? (json["durationMs"] as? Int)
        ?? 0
    }
    return [
      "title": (json["title"] as? String) ?? "",
      "durationMs": durationMs,
      "segmentCount": max(segs.count, pcm == nil ? 0 : 1),
    ]
  }

  private func recoverAbandonedSession(result: @escaping FlutterResult) {
    guard let json = readAbandonedSession() else {
      result(nil)
      return
    }
    if let pcm = abandonedPcmPath(json) {
      CrashSafeWavWriter.repairHeader(path: pcm)
      let leftoverSegs = (json["segments"] as? [String]) ?? []
      for path in leftoverSegs {
        try? FileManager.default.removeItem(atPath: path)
      }
      clearLiveSessionFile()
      result([
        "path": pcm,
        "durationMs": CrashSafeWavWriter.durationMs(path: pcm),
      ])
      return
    }
    let segs = ((json["segments"] as? [String]) ?? []).filter { path in
      let attrs = try? FileManager.default.attributesOfItem(atPath: path)
      let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
      return size > 1024
    }
    guard !segs.isEmpty else {
      discardAbandonedSession()
      result(nil)
      return
    }
    let durationMs = (json["durationMs"] as? NSNumber)?.intValue
      ?? (json["durationMs"] as? Int)
      ?? 0
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let path = self.resolveFinalRecordingPath(from: segs)
      DispatchQueue.main.async {
        self.clearLiveSessionFile()
        guard let path, !path.isEmpty else {
          result(nil)
          return
        }
        result([
          "path": path,
          "durationMs": durationMs,
        ])
      }
    }
  }

  private func discardAbandonedSession() {
    if let json = readAbandonedSession() {
      let segs = (json["segments"] as? [String]) ?? []
      for path in segs {
        try? FileManager.default.removeItem(atPath: path)
      }
      if let pcm = json["pcmPath"] as? String, !pcm.isEmpty {
        try? FileManager.default.removeItem(atPath: pcm)
      }
    }
    closeCrashWav(deleteFile: true)
    clearLiveSessionFile()
  }

  private func closeCrashWav(deleteFile: Bool) {
    crashWav?.close()
    crashWav = nil
    if deleteFile {
      try? FileManager.default.removeItem(at: livePcmURL())
    }
  }

  fileprivate func setRecorderEventSink(_ sink: FlutterEventSink?) {
    recorderEventLock.lock()
    recorderEventSink = sink
    recorderEventLock.unlock()
  }

  private func emitRecorderEvent(_ payload: [String: Any]) {
    recorderEventLock.lock()
    let sink = recorderEventSink
    recorderEventLock.unlock()
    guard let sink else { return }
    DispatchQueue.main.async {
      sink(payload)
    }
  }

  @objc private func handleMediaServicesReset(_ note: Notification) {
    guard isRecording else { return }
    autoPauseForInterruption(reason: "mediaServicesReset", allowAutoResume: true)
  }

  /// 外设断开等真实路由丢失时落盘暂停。
  /// 注意：不要把 `.categoryChange` / `.override` 当成抢麦——它们会在本 App
  /// 调用 setCategory、defaultToSpeaker 时触发，会造成误报并弄丢空片段。
  @objc private func handleAudioRouteChange(_ note: Notification) {
    guard isRecording, !isPaused else { return }
    if let until = ignoreRouteChangeUntil, Date() < until {
      return
    }
    guard let info = note.userInfo,
      let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
    else {
      return
    }
    switch reason {
    case .oldDeviceUnavailable:
      // 耳机拔出等：采集可能中断，先落盘暂停，由用户点继续。
      autoPauseForInterruption(reason: "routeDeviceLost", allowAutoResume: false)
    default:
      break
    }
  }

  @objc private func handleAppDidEnterBackground(_ note: Notification) {
    guard isRecording else { return }
    needsCaptureRebuild = true
    if isPaused {
      // 暂停后熄屏时 AVAssetWriter / AVAudioEngine 容易失效，先落盘当前片段。
      finalizeCurrentSegmentIfNeeded()
      teardownAudioEngine()
    } else if sessionTracking {
      rotateLiveSegmentIfNeeded()
    }
    persistLiveSession()
  }

  @objc private func handleAppWillEnterForeground(_ note: Notification) {
    guard isRecording else { return }
    needsCaptureRebuild = true
    tryNativeResumeAfterSystemInterruption()
  }

  // MARK: - XGPushDelegate

  /// 点击通知可能早于 Flutter 引擎初始化，先暂存 payload，待桥接完成后再转发。
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    if let bridge = tpnsBridge {
      bridge.handleNotificationClicked(userInfo: userInfo)
    } else {
      pendingTpnsNotificationClick = userInfo
    }
    completionHandler()
  }

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

  /// 持久化录音目录（不用 NSTemporaryDirectory，避免系统清 tmp 导致会议录音丢失）。
  private func voiceRecordingDirectory() -> String {
    let fm = FileManager.default
    let base =
      fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("voice_recordings", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    var mutableDir = dir
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutableDir.setResourceValues(values)
    return dir.path
  }

  private func newVoiceRecordingPath(prefix: String = "voice") -> String {
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    return (voiceRecordingDirectory() as NSString)
      .appendingPathComponent("\(prefix)-\(stamp).m4a")
  }

  private func startRecord(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    sessionTitle = ((args?["title"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    sessionTracking = args?["persistSession"] as? Bool ?? false
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
    let tracking = sessionTracking
    let title = sessionTitle
    stopInternal(deleteFile: true)
    sessionTracking = tracking
    sessionTitle = title
    segmentPaths = []
    needsCaptureRebuild = false
    let m4a = newVoiceRecordingPath(prefix: "voice")
    do {
      try prepareAudioSessionForRecording()

      let writer = StreamingAacM4aWriter()
      try writer.start(url: URL(fileURLWithPath: m4a))
      m4aWriter = writer
      outputPath = m4a
      if tracking {
        closeCrashWav(deleteFile: true)
        crashWav = try? CrashSafeWavWriter(path: livePcmURL().path)
      }

      try setupAudioEngine()

      recordStartedAt = Date()
      activeSegmentStartedAt = Date()
      accumulatedDurationMs = 0
      isRecording = true
      isPaused = false
      pausedBySystemInterruption = false
      persistLiveSession()
      startSegmentRotateTimer()
      result(true)
    } catch {
      stopInternal(deleteFile: true)
      result(FlutterError(code: "AUDIO_START_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func prepareAudioSessionForRecording() throws {
    let session = AVAudioSession.sharedInstance()
    // 不使用 mixWithOthers：会议录音需要独占麦克风，其他语音软件抢麦时才能收到中断通知。
    // 自身改 category / 扬声器会触发 routeChange，短暂忽略以免误暂停。
    ignoreRouteChangeUntil = Date().addingTimeInterval(1.5)
    try session.setCategory(
      .playAndRecord,
      mode: .spokenAudio,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    try session.setPreferredSampleRate(16000)
    try session.setActive(true, options: [])
  }

  private func setupAudioEngine() throws {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let format = input.inputFormat(forBus: 0)
    audioConverter = AVAudioConverter(from: format, to: targetFormat)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      self?.consumeAudioBuffer(buffer)
    }
    try engine.start()
    audioEngine = engine
  }

  private func teardownAudioEngine() {
    if let engine = audioEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    audioEngine = nil
    audioConverter = nil
  }

  private func startNewSegmentWriter() throws {
    let m4a = newVoiceRecordingPath(prefix: "voice")
    let writer = StreamingAacM4aWriter()
    try writer.start(url: URL(fileURLWithPath: m4a))
    m4aWriter = writer
    outputPath = m4a
  }

  private func finalizeCurrentSegmentIfNeeded() {
    guard let writer = m4aWriter, let path = outputPath, !path.isEmpty else {
      m4aWriter = nil
      outputPath = nil
      return
    }
    let ok = writer.finish()
    m4aWriter = nil
    outputPath = nil
    if ok {
      segmentPaths.append(path)
      persistLiveSession()
    } else {
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  private func stopRecord(result: @escaping FlutterResult, deleteFile: Bool) {
    let durationMs = stopInternal(deleteFile: deleteFile, mergeIfNeeded: false)
    if deleteFile {
      result(nil)
      return
    }
    let paths = pendingMergeSegmentPaths
    pendingMergeSegmentPaths = []
    if paths.isEmpty {
      guard let path = outputPath, !path.isEmpty else {
        result(nil)
        return
      }
      result([
        "path": path,
        "durationMs": durationMs
      ])
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      var finalPath = self.resolveFinalRecordingPath(from: paths)
      if let path = finalPath, !path.isEmpty {
        try? FileManager.default.removeItem(at: self.livePcmURL())
      } else {
        let pcmPath = self.livePcmURL().path
        let pcmSize = (try? FileManager.default.attributesOfItem(atPath: pcmPath)[.size] as? NSNumber)?
          .intValue ?? 0
        if pcmSize > 44 {
          CrashSafeWavWriter.repairHeader(path: pcmPath)
          finalPath = pcmPath
        }
      }
      DispatchQueue.main.async {
        self.outputPath = finalPath
        guard let path = finalPath, !path.isEmpty else {
          result(nil)
          return
        }
        result([
          "path": path,
          "durationMs": durationMs
        ])
      }
    }
  }

  private func pauseRecord(result: @escaping FlutterResult) {
    guard isRecording else {
      result(false)
      return
    }
    if isPaused {
      result(true)
      return
    }
    pausedBySystemInterruption = false
    accumulatedDurationMs += currentSegmentDurationMs()
    activeSegmentStartedAt = nil
    isPaused = true
    needsCaptureRebuild = true
    finalizeCurrentSegmentIfNeeded()
    teardownAudioEngine()
    crashWav?.flushHeader()
    persistLiveSession()
    result(true)
  }

  private func resumeRecord(result: @escaping FlutterResult) {
    guard isRecording else {
      result(false)
      return
    }
    if !isPaused {
      result(true)
      return
    }
    do {
      try resumeCaptureAfterPause()
      pausedBySystemInterruption = false
      clearRecordingPausedNotification()
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
  private func stopInternal(deleteFile: Bool, mergeIfNeeded: Bool = true) -> Int {
    let durationMs = currentDurationMs()
    let cancelTrackedSession = deleteFile && isRecording && sessionTracking
    let stopTrackedSession = isRecording && sessionTracking
    isRecording = false
    isPaused = false
    pausedBySystemInterruption = false
    needsCaptureRebuild = false
    ignoreRouteChangeUntil = nil
    clearRecordingPausedNotification()
    rotateTimer?.invalidate()
    rotateTimer = nil
    teardownAudioEngine()
    recordStartedAt = nil
    activeSegmentStartedAt = nil
    accumulatedDurationMs = 0

    if deleteFile {
      m4aWriter?.abort()
      m4aWriter = nil
      if let path = outputPath {
        try? FileManager.default.removeItem(atPath: path)
      }
      outputPath = nil
      for path in segmentPaths {
        try? FileManager.default.removeItem(atPath: path)
      }
      segmentPaths.removeAll()
      pendingMergeSegmentPaths = []
      if stopTrackedSession {
        closeCrashWav(deleteFile: true)
      }
      if cancelTrackedSession {
        discardAbandonedSession()
      }
      if stopTrackedSession {
        sessionTracking = false
        sessionTitle = ""
      }
      return durationMs
    }

    crashWav?.flushHeader()
    closeCrashWav(deleteFile: false)
    finalizeCurrentSegmentIfNeeded()
    if stopTrackedSession {
      clearLiveSessionFile()
      sessionTracking = false
      sessionTitle = ""
    }
    let paths = segmentPaths
    segmentPaths.removeAll()
    pendingMergeSegmentPaths = []
    let pcmPath = livePcmURL().path
    let pcmSize = (try? FileManager.default.attributesOfItem(atPath: pcmPath)[.size] as? NSNumber)?
      .intValue ?? 0
    let pcmOk = pcmSize > 44

    guard !paths.isEmpty else {
      if pcmOk {
        outputPath = pcmPath
        return CrashSafeWavWriter.durationMs(path: pcmPath)
      }
      outputPath = nil
      return durationMs
    }

    if paths.count == 1 {
      outputPath = paths[0]
      if pcmOk {
        try? FileManager.default.removeItem(atPath: pcmPath)
      }
      return durationMs
    }

    if !mergeIfNeeded {
      pendingMergeSegmentPaths = paths
      outputPath = pcmOk ? pcmPath : nil
      return durationMs
    }

    outputPath = resolveFinalRecordingPath(from: paths)
    if let out = outputPath, !out.isEmpty, pcmOk {
      try? FileManager.default.removeItem(atPath: pcmPath)
    } else if pcmOk {
      outputPath = pcmPath
    }
    return durationMs
  }

  private func resolveFinalRecordingPath(from paths: [String]) -> String? {
    if paths.isEmpty { return nil }
    if paths.count == 1 { return paths[0] }

    let merged = newVoiceRecordingPath(prefix: "voice-merged")
    if mergeAudioSegments(paths, to: merged) {
      for path in paths where path != merged {
        try? FileManager.default.removeItem(atPath: path)
      }
      return merged
    }

    // 合并失败时保留体积最大的片段，避免整段录音丢失。
    let keep = Self.largestExistingAudioPath(paths)
    if let keep {
      for path in paths where path != keep {
        try? FileManager.default.removeItem(atPath: path)
      }
    } else {
      for path in paths {
        try? FileManager.default.removeItem(atPath: path)
      }
    }
    return keep
  }

  private static func largestExistingAudioPath(_ paths: [String]) -> String? {
    var best: String?
    var bestSize: Int = -1
    for path in paths {
      guard FileManager.default.fileExists(atPath: path) else { continue }
      let attrs = try? FileManager.default.attributesOfItem(atPath: path)
      let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
      if size > bestSize {
        bestSize = size
        best = path
      }
    }
    return best
  }

  private func mergeAudioSegments(_ paths: [String], to outputPath: String) -> Bool {
    guard !paths.isEmpty else { return false }
    if paths.count == 1 {
      let src = paths[0]
      if src == outputPath { return true }
      do {
        if FileManager.default.fileExists(atPath: outputPath) {
          try FileManager.default.removeItem(atPath: outputPath)
        }
        try FileManager.default.copyItem(atPath: src, toPath: outputPath)
        return true
      } catch {
        return false
      }
    }

    let composition = AVMutableComposition()
    guard
      let compTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      return false
    }

    var cursor = CMTime.zero
    for path in paths {
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let srcTrack = asset.tracks(withMediaType: .audio).first else { continue }
      let duration = asset.duration
      guard duration.isValid, duration.seconds > 0 else { continue }
      do {
        try compTrack.insertTimeRange(
          CMTimeRange(start: .zero, duration: duration),
          of: srcTrack,
          at: cursor
        )
        cursor = CMTimeAdd(cursor, duration)
      } catch {
        return false
      }
    }

    guard cursor.seconds > 0 else { return false }

    if FileManager.default.fileExists(atPath: outputPath) {
      try? FileManager.default.removeItem(atPath: outputPath)
    }

    guard
      let export = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetAppleM4A
      )
    else {
      return false
    }
    export.outputURL = URL(fileURLWithPath: outputPath)
    export.outputFileType = .m4a

    let group = DispatchGroup()
    group.enter()
    var ok = false
    export.exportAsynchronously {
      ok = export.status == .completed
      group.leave()
    }
    group.wait()
    guard ok else {
      try? FileManager.default.removeItem(atPath: outputPath)
      return false
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    return size > 0
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
    m4aWriter?.appendPcmInt16(data)
    crashWav?.write(data)
    streamLock.lock()
    let sink = streamSink
    streamLock.unlock()

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

  private func convertWavToM4a(
    inputPath: String,
    outputPath: String,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let bitRate = 32_000
      let inputURL = URL(fileURLWithPath: inputPath)
      let outputURL = URL(fileURLWithPath: outputPath)
      if FileManager.default.fileExists(atPath: outputPath) {
        try? FileManager.default.removeItem(at: outputURL)
      }

      if self.convertWavToM4aWithReaderWriter(
        inputURL: inputURL,
        outputURL: outputURL,
        bitRate: bitRate
      ) {
        DispatchQueue.main.async { result(outputPath) }
        return
      }

      // 回退：Apple 预设（码率不可控，但兼容性更好）
      let asset = AVURLAsset(url: inputURL)
      guard let export = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetAppleM4A
      ) else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "CONVERT_FAILED",
              message: "export session unavailable",
              details: nil
            ))
        }
        return
      }
      export.outputURL = outputURL
      export.outputFileType = .m4a
      export.exportAsynchronously {
        DispatchQueue.main.async {
          if export.status == .completed {
            result(outputPath)
          } else {
            result(
              FlutterError(
                code: "CONVERT_FAILED",
                message: export.error?.localizedDescription ?? "export failed",
                details: nil
              ))
          }
        }
      }
    }
  }

  /// 与 Android 对齐：16k/mono AAC-LC 32kbps。
  private func convertWavToM4aWithReaderWriter(
    inputURL: URL,
    outputURL: URL,
    bitRate: Int
  ) -> Bool {
    let asset = AVURLAsset(url: inputURL)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      return false
    }

    let reader: AVAssetReader
    let writer: AVAssetWriter
    do {
      reader = try AVAssetReader(asset: asset)
      writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
    } catch {
      return false
    }

    let readerOutput = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]
    )
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else { return false }
    reader.add(readerOutput)

    let writerInput = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: bitRate,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
      ]
    )
    writerInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(writerInput) else { return false }
    writer.add(writerInput)

    guard reader.startReading() else { return false }
    guard writer.startWriting() else { return false }
    writer.startSession(atSourceTime: .zero)

    let group = DispatchGroup()
    group.enter()
    var ok = true

    writerInput.requestMediaDataWhenReady(on: DispatchQueue.global(qos: .userInitiated)) {
      while writerInput.isReadyForMoreMediaData {
        if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
          if !writerInput.append(sampleBuffer) {
            ok = false
            reader.cancelReading()
            writer.cancelWriting()
            group.leave()
            return
          }
        } else {
          writerInput.markAsFinished()
          writer.finishWriting {
            ok = ok && writer.status == .completed
            group.leave()
          }
          return
        }
      }
    }

    group.wait()
    guard ok else {
      try? FileManager.default.removeItem(at: outputURL)
      return false
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    return size > 0
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

private final class AudioRecorderEventHandler: NSObject, FlutterStreamHandler {
  weak var owner: AppDelegate?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError?
  {
    owner?.setRecorderEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    owner?.setRecorderEventSink(nil)
    return nil
  }
}

private extension FixedWidthInteger {
  var leData: Data {
    var v = self.littleEndian
    return Data(bytes: &v, count: MemoryLayout<Self>.size)
  }
}

/// 边录边追加 WAV。文件随时可播，进程被杀后按实际长度修复头即可。
final class CrashSafeWavWriter {
  private let handle: FileHandle
  private var dataBytes = 0
  private var writesSinceHeader = 0
  private let lock = NSLock()
  private let sampleRate = 16_000
  private let channels = 1
  private let bitsPerSample = 16

  init(path: String) throws {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(at: url)
    }
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let handle = FileHandle(forUpdatingAtPath: path) else {
      throw NSError(
        domain: "dunes.audio",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "cannot open crash-safe wav"]
      )
    }
    self.handle = handle
    try rewriteHeaderLocked()
  }

  func write(_ data: Data) {
    guard !data.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }
    handle.seek(toFileOffset: 44 + UInt64(dataBytes))
    handle.write(data)
    dataBytes += data.count
    writesSinceHeader += 1
    if writesSinceHeader >= 40 {
      try? rewriteHeaderLocked()
    }
  }

  func flushHeader() {
    lock.lock()
    defer { lock.unlock() }
    try? rewriteHeaderLocked()
  }

  func close() {
    lock.lock()
    defer { lock.unlock() }
    try? rewriteHeaderLocked()
    try? handle.close()
  }

  private func rewriteHeaderLocked() throws {
    let pos = handle.offsetInFile
    handle.seek(toFileOffset: 0)
    handle.write(Self.headerBytes(dataLength: dataBytes, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample))
    handle.seek(toFileOffset: pos)
    writesSinceHeader = 0
  }

  static func repairHeader(path: String) {
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    guard size > 44 else { return }
    guard let handle = FileHandle(forUpdatingAtPath: path) else { return }
    defer { try? handle.close() }
    handle.seek(toFileOffset: 0)
    handle.write(headerBytes(dataLength: size - 44, sampleRate: 16_000, channels: 1, bitsPerSample: 16))
  }

  static func durationMs(path: String) -> Int {
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
      .intValue ?? 0
    guard size > 44 else { return 0 }
    return max(0, (size - 44) / 32)
  }

  private static func headerBytes(
    dataLength: Int,
    sampleRate: Int,
    channels: Int,
    bitsPerSample: Int
  ) -> Data {
    let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
    let blockAlign = UInt16(channels * bitsPerSample / 8)
    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.append(UInt32(36 + dataLength).leData)
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    data.append(UInt32(16).leData)
    data.append(UInt16(1).leData)
    data.append(UInt16(channels).leData)
    data.append(UInt32(sampleRate).leData)
    data.append(byteRate.leData)
    data.append(blockAlign.leData)
    data.append(UInt16(bitsPerSample).leData)
    data.append("data".data(using: .ascii)!)
    data.append(UInt32(dataLength).leData)
    return data
  }
}

/// 边录边编码 PCM → AAC/m4a（16k/mono/32kbps）。
final class StreamingAacM4aWriter {
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var startedSession = false
  private var sampleCount: Int64 = 0
  private let sampleRate: Double = 16_000
  private let channels: UInt32 = 1

  func start(url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    let assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channels,
      AVEncoderBitRateKey: 32_000,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
    writerInput.expectsMediaDataInRealTime = true
    guard assetWriter.canAdd(writerInput) else {
      throw NSError(
        domain: "dunes.audio",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "cannot add audio writer input"]
      )
    }
    assetWriter.add(writerInput)
    guard assetWriter.startWriting() else {
      throw assetWriter.error
        ?? NSError(
          domain: "dunes.audio",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "asset writer start failed"]
        )
    }
    writer = assetWriter
    input = writerInput
    startedSession = false
    sampleCount = 0
  }

  func appendPcmInt16(_ data: Data) {
    guard let input, let writer, !data.isEmpty else { return }
    let frameCount = data.count / MemoryLayout<Int16>.size
    if frameCount <= 0 { return }
    guard let sampleBuffer = makeSampleBuffer(from: data, frameCount: frameCount) else { return }
    if !startedSession {
      writer.startSession(atSourceTime: .zero)
      startedSession = true
    }
    var waitCount = 0
    while !input.isReadyForMoreMediaData && waitCount < 200 {
      Thread.sleep(forTimeInterval: 0.005)
      waitCount += 1
    }
    guard input.isReadyForMoreMediaData else { return }
    if input.append(sampleBuffer) {
      sampleCount += Int64(frameCount)
    }
  }

  func finish() -> Bool {
    // 尚未写入任何 PCM 时不能 finishWriting（未 startSession），否则会失败并删掉空文件。
    if !startedSession || sampleCount <= 0 {
      abort()
      return false
    }
    input?.markAsFinished()
    let group = DispatchGroup()
    group.enter()
    var ok = false
    writer?.finishWriting {
      ok = self.writer?.status == .completed
      group.leave()
    }
    group.wait()
    let path = writer?.outputURL.path ?? ""
    cleanup()
    guard ok else {
      try? FileManager.default.removeItem(atPath: path)
      return false
    }
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
    if size <= 0 {
      try? FileManager.default.removeItem(atPath: path)
      return false
    }
    return true
  }

  func abort() {
    input?.markAsFinished()
    writer?.cancelWriting()
    if let path = writer?.outputURL.path {
      try? FileManager.default.removeItem(atPath: path)
    }
    cleanup()
  }

  private func cleanup() {
    writer = nil
    input = nil
    startedSession = false
    sampleCount = 0
  }

  private func makeSampleBuffer(from data: Data, frameCount: Int) -> CMSampleBuffer? {
    var blockBuffer: CMBlockBuffer?
    let status = data.withUnsafeBytes { raw -> OSStatus in
      guard let base = raw.baseAddress else { return -1 }
      return CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: data.count,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: data.count,
        flags: 0,
        blockBufferOut: &blockBuffer
      )
    }
    guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }

    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      CMBlockBufferReplaceDataBytes(
        with: base,
        blockBuffer: blockBuffer,
        offsetIntoDestination: 0,
        dataLength: data.count
      )
    }

    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: channels,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    var formatDesc: CMAudioFormatDescription?
    guard
      CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDesc
      ) == noErr,
      let formatDesc
    else {
      return nil
    }

    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: Int32(sampleRate)),
      presentationTimeStamp: CMTime(value: sampleCount, timescale: Int32(sampleRate)),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard
      CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDesc,
        sampleCount: CMItemCount(frameCount),
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
      ) == noErr
    else {
      return nil
    }
    return sampleBuffer
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
  private var isAttached = false
  private var isDartHandlerReady = false
  private var pendingNotificationClick: [String: Any]?

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
    isAttached = true
    isDartHandlerReady = false
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

  func handleNotificationClicked(userInfo: [AnyHashable: Any]) {
    pendingNotificationClick = Self.notificationClickPayload(from: userInfo)
    flushPendingNotificationClick()
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
      if let raw = userInfo[key] as? [AnyHashable: Any], let badge = parseBadgeDictionary(raw) {
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

  private static func parseBadgeDictionary(_ raw: [AnyHashable: Any]) -> Int? {
    for key in ["badgeCount", "badge"] {
      if let value = raw[key] as? Int, value >= 0 {
        return value
      }
      if let value = raw[key] as? NSNumber, value.intValue >= 0 {
        return value.intValue
      }
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
    case "clearConversationNotifications":
      clearConversationNotifications(call, result: result)
    case "requestAuthorization":
      requestAuthorization(result: result)
    case "isMiuiDevice":
      result(false)
    case "consumePendingNotificationClick":
      isDartHandlerReady = true
      flushPendingNotificationClick()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func flushPendingNotificationClick() {
    guard isAttached, isDartHandlerReady, let payload = pendingNotificationClick else { return }
    pendingNotificationClick = nil
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("onNotificationClicked", arguments: payload)
    }
  }

  private static func notificationClickPayload(from userInfo: [AnyHashable: Any]) -> [String: Any] {
    var payload: [String: Any] = [:]
    if let aps = userInfo["aps"] as? [AnyHashable: Any],
      let alert = aps["alert"] as? [AnyHashable: Any]
    {
      if let title = notificationText(alert["title"]) {
        payload["title"] = title
      }
      if let body = notificationText(alert["body"]) {
        payload["body"] = body
      }
    }
    if let title = notificationText(userInfo["title"]) {
      payload["title"] = title
    }
    if let body = notificationText(userInfo["content"] ?? userInfo["body"]) {
      payload["body"] = body
    }

    for key in ["custom_content", "custom"] {
      guard let raw = userInfo[key] else { continue }
      if let custom = notificationJSON(raw) {
        payload["customContent"] = custom
        for field in ["schemaVersion", "eventType", "conversationId", "messageId", "clickAction", "tab", "noticeId"] {
          if let value = custom[field] {
            payload[field] = value
          }
        }
        break
      }
      if let text = notificationText(raw) {
        payload["customContent"] = text
      }
    }
    return payload
  }

  private static func notificationText(_ value: Any?) -> String? {
    if let string = value as? String {
      return string.precomposedStringWithCanonicalMapping
    }
    if let string = value as? NSString {
      return string as String
    }
    if let data = value as? Data {
      return String(data: data, encoding: .utf8)
    }
    return nil
  }

  private static func notificationJSON(_ value: Any) -> [String: Any]? {
    if let object = value as? [String: Any] {
      return object
    }
    if let object = value as? [AnyHashable: Any] {
      var result: [String: Any] = [:]
      for (key, value) in object {
        guard let key = key as? String else { continue }
        result[key] = value
      }
      return result
    }
    guard let raw = notificationText(value),
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data),
      let result = object as? [String: Any]
    else {
      return nil
    }
    return result
  }

  private static func int64Value(_ value: Any?) -> Int64? {
    if let number = value as? NSNumber {
      return number.int64Value
    }
    if let integer = value as? Int {
      return Int64(integer)
    }
    if let text = value as? String {
      return Int64(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
  }

  private func clearConversationNotifications(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let conversationId = Self.int64Value(args["conversationId"]),
      conversationId > 0
    else {
      result(0)
      return
    }

    let center = UNUserNotificationCenter.current()
    center.getDeliveredNotifications { notifications in
      let identifiers = notifications.compactMap { notification -> String? in
        let payload = Self.notificationClickPayload(
          from: notification.request.content.userInfo
        )
        let eventType = String(describing: payload["eventType"] ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
        guard eventType == "im",
          let notificationConversationId = Self.int64Value(payload["conversationId"]),
          notificationConversationId == conversationId
        else {
          return nil
        }
        return notification.request.identifier
      }

      if !identifiers.isEmpty {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
      }
      DispatchQueue.main.async {
        result(identifiers.count)
      }
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

final class MeetingAudioFilePicker: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?

  func pick(result: @escaping FlutterResult) {
    if pending != nil {
      result(FlutterError(code: "BUSY", message: "already picking", details: nil))
      return
    }
    pending = result
    let types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    guard let presenter = Self.topViewController() else {
      pending = nil
      result(FlutterError(code: "NO_VC", message: "无法打开文件选择器", details: nil))
      return
    }
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let src = urls.first else {
      finish(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let dest = try Self.copyToDocuments(src)
        DispatchQueue.main.async { self?.finish(dest) }
      } catch {
        DispatchQueue.main.async {
          self?.finish(
            FlutterError(
              code: "COPY_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    let callback = pending
    pending = nil
    callback?(value)
  }

  private static func copyToDocuments(_ src: URL) throws -> String {
    let accessing = src.startAccessingSecurityScopedResource()
    defer {
      if accessing { src.stopAccessingSecurityScopedResource() }
    }
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let dir = docs.appendingPathComponent("meeting_uploads", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var name = src.lastPathComponent
    if name.isEmpty { name = "recording.m4a" }
    let dest = dir.appendingPathComponent(
      "meeting_pick_\(Int(Date().timeIntervalSince1970 * 1000))_\(name)"
    )
    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.copyItem(at: src, to: dest)
    let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
    let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
    if size <= 0 {
      throw NSError(
        domain: "dunes.meeting",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "录音文件保存失败"]
      )
    }
    return dest.path
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let window = windows.first(where: \.isKeyWindow) ?? windows.first
    var vc = window?.rootViewController
    while let presented = vc?.presentedViewController {
      vc = presented
    }
    return vc
  }
}
