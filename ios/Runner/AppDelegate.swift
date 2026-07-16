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
  private let voiceEventsChannelName = "dunes/audio_recorder_events"
  private let meetingAudioChannelName = "dunes/meeting_audio"
  private var audioEngine: AVAudioEngine?
  private var m4aWriter: StreamingAacM4aWriter?
  private var recordStartedAt: Date?
  private var activeSegmentStartedAt: Date?
  private var accumulatedDurationMs: Int = 0
  private var outputPath: String?
  private var segmentPaths: [String] = []
  private var needsCaptureRebuild = false
  private var isRecording = false
  private var isPaused = false
  /// 忽略自身 setCategory / defaultToSpeaker 触发的路由回调，避免误报「被其他软件占用」。
  private var ignoreRouteChangeUntil: Date?
  private var streamSink: FlutterEventSink?
  private let streamLock = NSLock()
  private var recorderEventSink: FlutterEventSink?
  private let recorderEventLock = NSLock()
  private let recorderEventHandler = AudioRecorderEventHandler()
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

    recorderEventHandler.owner = self
    let eventsChannel = FlutterEventChannel(
      name: voiceEventsChannelName,
      binaryMessenger: messenger
    )
    eventsChannel.setStreamHandler(recorderEventHandler)

    let meetingAudioChannel = FlutterMethodChannel(
      name: meetingAudioChannelName,
      binaryMessenger: messenger
    )
    meetingAudioChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      switch call.method {
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
      autoPauseForInterruption(reason: "interruption")
    case .ended:
      guard isRecording else { return }
      // 仅在系统建议恢复时通知 Flutter 自动续录。
      let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
      if options.contains(.shouldResume) || optionsRaw == 0 {
        emitRecorderEvent(["kind": "interruptionEnded"])
      }
    @unknown default:
      break
    }
  }

  /// 来电等系统音频中断：立即落盘当前片段并暂停，避免 stop 时录音丢失。
  private func autoPauseForInterruption(reason: String) {
    guard isRecording else { return }
    if !isPaused {
      accumulatedDurationMs += currentSegmentDurationMs()
      activeSegmentStartedAt = nil
      isPaused = true
      emitRecorderEvent(["kind": "paused", "reason": reason])
    }
    needsCaptureRebuild = true
    finalizeCurrentSegmentIfNeeded()
    teardownAudioEngine()
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
    autoPauseForInterruption(reason: "mediaServicesReset")
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
      autoPauseForInterruption(reason: "routeDeviceLost")
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
    }
  }

  @objc private func handleAppWillEnterForeground(_ note: Notification) {
    guard isRecording else { return }
    needsCaptureRebuild = true
  }

  private func resumeEngineAfterInterruption() {
    guard isRecording, !isPaused else { return }
    do {
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
    segmentPaths = []
    needsCaptureRebuild = false
    let m4a = newVoiceRecordingPath(prefix: "voice")
    do {
      try prepareAudioSessionForRecording()

      let writer = StreamingAacM4aWriter()
      try writer.start(url: URL(fileURLWithPath: m4a))
      m4aWriter = writer
      outputPath = m4a

      try setupAudioEngine()

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
    } else {
      try? FileManager.default.removeItem(atPath: path)
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
    needsCaptureRebuild = false
    ignoreRouteChangeUntil = nil
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
      return durationMs
    }

    finalizeCurrentSegmentIfNeeded()
    let paths = segmentPaths
    segmentPaths.removeAll()

    guard !paths.isEmpty else {
      outputPath = nil
      return durationMs
    }

    let finalPath: String?
    if paths.count == 1 {
      finalPath = paths[0]
    } else {
      let merged = newVoiceRecordingPath(prefix: "voice-merged")
      if mergeAudioSegments(paths, to: merged) {
        finalPath = merged
        for path in paths where path != merged {
          try? FileManager.default.removeItem(atPath: path)
        }
      } else {
        // 合并失败时保留体积最大的片段，避免整段录音丢失。
        finalPath = Self.largestExistingAudioPath(paths)
        if let keep = finalPath {
          for path in paths where path != keep {
            try? FileManager.default.removeItem(atPath: path)
          }
        } else {
          for path in paths {
            try? FileManager.default.removeItem(atPath: path)
          }
        }
      }
    }

    outputPath = finalPath
    return durationMs
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
