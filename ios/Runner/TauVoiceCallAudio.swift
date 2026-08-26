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

/// PCM-only capture route for the τ phone; it does not share recorder state.
final class TauVoiceCallAudio: NSObject, FlutterStreamHandler {
  private let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: true
  )!
  private let eventStreamHandler = TauVoiceCallEventStreamHandler()
  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var eventSink: FlutterEventSink?
  private var capturing = false

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: "dunes/voice_call", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(nil)
          return
        }
        switch call.method {
        case "start":
          self.start(result: result)
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
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.defaultToSpeaker, .allowBluetooth]
      )
      try session.setPreferredSampleRate(16_000)
      try session.setActive(true)

      let newEngine = AVAudioEngine()
      let input = newEngine.inputNode
      let inputFormat = input.inputFormat(forBus: 0)
      guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
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
      try newEngine.start()
      engine = newEngine
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

  private func stop() {
    capturing = false
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    engine = nil
    converter = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
