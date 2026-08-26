import AVFoundation
import CallKit
import Flutter
import Foundation

/// Reports the in-app τ phone as a system CallKit call.
///
/// This bridge deliberately supports outgoing calls only. Incoming calls need a
/// server-driven wake-up path and are therefore not implemented with PushKit.
final class TauVoiceCallCallKit: NSObject, CXProviderDelegate {
  static let channelName = "dunes/tau_voice_call_callkit"

  private let provider: CXProvider
  private let callController = CXCallController()
  private var channel: FlutterMethodChannel?
  private var activeCallUUID: UUID?
  private var flutterRequestedEndCallUUIDs = Set<UUID>()

  init(messenger: FlutterBinaryMessenger) {
    let configuration = CXProviderConfiguration(
      localizedName: Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? "τ 电话"
    )
    configuration.supportsVideo = false
    configuration.maximumCallsPerCallGroup = 1
    configuration.maximumCallGroups = 1
    configuration.supportedHandleTypes = [.generic]
    provider = CXProvider(configuration: configuration)

    super.init()

    provider.setDelegate(self, queue: .main)
    let methodChannel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        self?.handle(call, result: result)
      }
    }
    channel = methodChannel
  }

  deinit {
    provider.invalidate()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startCall":
      let displayName = (call.arguments as? [String: Any])?["displayName"] as? String ?? "τ 电话"
      startCall(displayName: displayName, result: result)
    case "endCall":
      let callId = (call.arguments as? [String: Any])?["callId"] as? String
      endCall(callId: callId, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCall(displayName: String, result: @escaping FlutterResult) {
    guard activeCallUUID == nil else {
      result(
        FlutterError(
          code: "CALL_ALREADY_ACTIVE",
          message: "A τ phone CallKit call is already active.",
          details: activeCallUUID?.uuidString
        ))
      return
    }

    let uuid = UUID()
    activeCallUUID = uuid
    let handle = CXHandle(type: .generic, value: displayName)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = false

    callController.request(CXTransaction(action: action)) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let error {
          if self.activeCallUUID == uuid {
            self.activeCallUUID = nil
          }
          result(
            FlutterError(
              code: "CALLKIT_START_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          return
        }
        result(["callId": uuid.uuidString])
      }
    }
  }

  private func endCall(callId: String?, result: @escaping FlutterResult) {
    guard let uuid = callId.flatMap(UUID.init(uuidString:)) ?? activeCallUUID else {
      result(
        FlutterError(
          code: "NO_ACTIVE_CALL",
          message: "No τ phone CallKit call is active.",
          details: nil
        ))
      return
    }
    guard uuid == activeCallUUID else {
      result(
        FlutterError(
          code: "CALL_NOT_ACTIVE",
          message: "The requested τ phone CallKit call is not active.",
          details: callId
        ))
      return
    }

    flutterRequestedEndCallUUIDs.insert(uuid)
    callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      DispatchQueue.main.async {
        if let error {
          self?.flutterRequestedEndCallUUIDs.remove(uuid)
          result(
            FlutterError(
              code: "CALLKIT_END_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          return
        }
        result(nil)
      }
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    guard let uuid = activeCallUUID else { return }
    finishCall(uuid, source: "reset")
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard activeCallUUID == action.callUUID else {
      action.fail()
      return
    }

    let now = Date()
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: now)
    provider.reportOutgoingCall(with: action.callUUID, connectedAt: now)
    action.fulfill()
    emit("onCallStarted", arguments: ["callId": action.callUUID.uuidString])
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    action.fulfill()
    let source = flutterRequestedEndCallUUIDs.remove(action.callUUID) != nil ? "flutter" : "system"
    finishCall(action.callUUID, source: source)
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    if let endAction = action as? CXEndCallAction {
      let source = flutterRequestedEndCallUUIDs.remove(endAction.callUUID) != nil ? "flutter" : "system"
      finishCall(endAction.callUUID, source: source)
    } else if let startAction = action as? CXStartCallAction, activeCallUUID == startAction.callUUID {
      activeCallUUID = nil
    }
    action.fail()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}

  private func finishCall(_ uuid: UUID, source: String) {
    guard activeCallUUID == uuid else { return }
    activeCallUUID = nil
    emit(
      "onCallEnded",
      arguments: [
        "callId": uuid.uuidString,
        "source": source,
      ]
    )
  }

  private func emit(_ method: String, arguments: [String: Any]) {
    channel?.invokeMethod(method, arguments: arguments)
  }
}
