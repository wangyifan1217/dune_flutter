import AVFoundation
import Flutter

/// Accepts Flutter's lifecycle-event subscription. Hangup itself is delivered
/// through CallKit; this channel exists so iOS does not throw MissingPluginException.
private final class TauVoiceCallEventStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil
  }
}

/// PCM capture and reply playback for the τ phone, both on one AVAudioEngine.
///
/// just_audio/AVPlayer cannot start during a CallKit voiceChat session
/// (OSStatus 561017449 / !ply). Playback therefore goes through AVAudioPlayerNode.
final class TauVoiceCallAudio: NSObject, FlutterStreamHandler {
  static weak var shared: TauVoiceCallAudio?

  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: true
  )!
  private let eventStreamHandler = TauVoiceCallEventStreamHandler()
  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var converter: AVAudioConverter?
  private var eventSink: FlutterEventSink?
  private var capturing = false
  private var playResult: FlutterResult?
  private var playGeneration = 0
  private var playFile: AVAudioFile?
  private var playFileURL: URL?
  private var routeObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    Self.shared = self
    FlutterMethodChannel(name: "dunes/voice_call", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }
        switch call.method {
        case "start":
          self.start(result: result)
        case "play":
          self.play(arguments: call.arguments, result: result)
        case "stopPlayback":
          self.stopPlayback()
          result(nil)
        case "stop", "cancel":
          self.stop()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "dunes/voice_call_pcm", binaryMessenger: messenger)
      .setStreamHandler(self)
    FlutterEventChannel(name: "dunes/voice_call_events", binaryMessenger: messenger)
      .setStreamHandler(eventStreamHandler)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  static func configureSession(activate: Bool) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth]
    )
    try routeToPreferredOutput()
    if activate {
      try session.setActive(true)
    }
  }

  /// Headphones / Bluetooth keep the system route; otherwise force speakerphone.
  static func routeToPreferredOutput() throws {
    let session = AVAudioSession.sharedInstance()
    if hasExternalHeadset(session) {
      try session.overrideOutputAudioPort(.none)
    } else {
      try session.overrideOutputAudioPort(.speaker)
    }
  }

  private static func hasExternalHeadset(_ session: AVAudioSession) -> Bool {
    session.currentRoute.outputs.contains { port in
      switch port.portType {
      case .headphones, .headsetMic, .bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .usbAudio, .carAudio:
        true
      default:
        false
      }
    }
  }

  func handleAudioSessionActivated() {
    do {
      try Self.configureSession(activate: false)
      if capturing {
        try ensureEngineRunning()
      }
    } catch {
      // CallKit already activated the session; engine restart is best-effort.
    }
  }

  private func start(result: @escaping FlutterResult) {
    if capturing {
      result(nil)
      return
    }
    let session = AVAudioSession.sharedInstance()
    if session.recordPermission == .undetermined {
      session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else {
            result(nil)
            return
          }
          guard granted else {
            result(FlutterError(
              code: "VOICE_CALL_PERMISSION_DENIED",
              message: "microphone denied",
              details: nil
            ))
            return
          }
          self.startCapture(result: result)
        }
      }
      return
    }
    guard session.recordPermission == .granted else {
      result(FlutterError(
        code: "VOICE_CALL_PERMISSION_DENIED",
        message: "microphone denied",
        details: nil
      ))
      return
    }
    startCapture(result: result)
  }

  private func startCapture(result: @escaping FlutterResult) {
    do {
      try Self.configureSession(activate: true)
      startListeningForRouteChanges()
      try ensureEngineRunning()
      capturing = true
      result(nil)
    } catch {
      stop()
      result(FlutterError(
        code: "VOICE_CALL_START_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func ensureEngineRunning() throws {
    if let engine, engine.isRunning {
      return
    }
    if engine != nil {
      teardownEngine()
    }

    let newEngine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    newEngine.attach(player)
    newEngine.connect(player, to: newEngine.mainMixerNode, format: nil)

    let input = newEngine.inputNode
    let inputFormat = input.inputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      throw NSError(
        domain: "dunes.voice_call",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "cannot create PCM converter"]
      )
    }
    converter = newConverter
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
      self?.emitPcm(buffer)
    }
    newEngine.mainMixerNode.outputVolume = 1
    try newEngine.start()
    engine = newEngine
    playerNode = player
  }

  private func play(arguments: Any?, result: @escaping FlutterResult) {
    let data: Data
    if let typed = arguments as? FlutterStandardTypedData {
      data = typed.data
    } else if let raw = arguments as? Data {
      data = raw
    } else {
      result(FlutterError(
        code: "VOICE_CALL_PLAY_FAILED",
        message: "missing wav bytes",
        details: nil
      ))
      return
    }

    completePlay()
    playGeneration += 1
    let generation = playGeneration
    do {
      try Self.configureSession(activate: true)
      try ensureEngineRunning()
      guard let engine, let playerNode else {
        throw NSError(
          domain: "dunes.voice_call",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "audio engine unavailable"]
        )
      }

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("tau_voice_\(UUID().uuidString).wav")
      try data.write(to: url, options: .atomic)
      let file = try AVAudioFile(forReading: url)
      playFileURL = url
      playFile = file
      playResult = result

      playerNode.stop()
      playerNode.reset()
      engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
      playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.playGeneration == generation else { return }
          self.completePlay()
        }
      }
      if !engine.isRunning {
        try engine.start()
      }
      playerNode.play()
    } catch {
      cleanupPlayFile()
      playResult = nil
      result(FlutterError(
        code: "VOICE_CALL_PLAY_FAILED",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  private func stopPlayback() {
    playGeneration += 1
    playerNode?.stop()
    completePlay()
  }

  private func completePlay() {
    guard let result = playResult else {
      cleanupPlayFile()
      return
    }
    playResult = nil
    cleanupPlayFile()
    result(nil)
  }

  private func cleanupPlayFile() {
    playFile = nil
    if let url = playFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    playFileURL = nil
  }

  private func emitPcm(_ input: AVAudioPCMBuffer) {
    guard capturing, let converter else { return }
    let capacity = AVAudioFrameCount(
      Double(input.frameLength) * targetFormat.sampleRate / input.format.sampleRate
    ) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
      return
    }
    var fed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
      guard !fed else {
        outStatus.pointee = .noDataNow
        return nil
      }
      fed = true
      outStatus.pointee = .haveData
      return input
    }
    guard status != .error, error == nil, output.frameLength > 0,
      let samples = output.int16ChannelData
    else {
      return
    }
    let data = Data(
      bytes: samples[0],
      count: Int(output.frameLength) * MemoryLayout<Int16>.size
    )
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(FlutterStandardTypedData(bytes: data))
    }
  }

  private func startListeningForRouteChanges() {
    guard routeObserver == nil else { return }
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      try? Self.routeToPreferredOutput()
    }
  }

  private func stopListeningForRouteChanges() {
    if let routeObserver {
      NotificationCenter.default.removeObserver(routeObserver)
      self.routeObserver = nil
    }
  }

  private func teardownEngine() {
    playerNode?.stop()
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      engine.reset()
    }
    engine = nil
    playerNode = nil
    converter = nil
  }

  private func stop() {
    capturing = false
    stopListeningForRouteChanges()
    stopPlayback()
    teardownEngine()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
