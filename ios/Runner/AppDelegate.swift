import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let voiceChannelName = "dunes/audio_recorder"
  private var recorder: AVAudioRecorder?
  private var recordStartedAt: Date?
  private var outputPath: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: voiceChannelName,
      binaryMessenger: engineBridge.binaryMessenger
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
    let path = "\(NSTemporaryDirectory())voice-\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
    let url = URL(fileURLWithPath: path)
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44100.0,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
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
