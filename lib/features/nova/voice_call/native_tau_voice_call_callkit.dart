import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A CallKit hangup action, initiated by iOS or by Flutter.
class TauVoiceCallHangup {
  const TauVoiceCallHangup({required this.callId, required this.source});

  final String callId;
  final String source;
}

/// Thin iOS-only facade for the τ phone's system CallKit lifecycle.
///
/// It does not start microphone capture or alter the Flutter call UI. Those
/// remain the responsibility of [NativeTauVoiceCallAudio] and its caller.
class NativeTauVoiceCallCallKit {
  NativeTauVoiceCallCallKit._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final NativeTauVoiceCallCallKit instance =
      NativeTauVoiceCallCallKit._();

  static const MethodChannel _channel = MethodChannel(
    'dunes/tau_voice_call_callkit',
  );
  final StreamController<TauVoiceCallHangup> _hangups =
      StreamController<TauVoiceCallHangup>.broadcast();

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Stream<TauVoiceCallHangup> get hangups => _hangups.stream;

  /// Starts the iOS system call and returns its CallKit UUID.
  ///
  /// Returns null outside iOS or when the app is running without the iOS
  /// native runner (for example, desktop development).
  Future<String?> startCall({String displayName = 'τ 电话'}) async {
    if (!isSupported) return null;
    try {
      final reply = await _channel.invokeMapMethod<String, dynamic>(
        'startCall',
        {'displayName': displayName},
      );
      return reply?['callId'] as String?;
    } on MissingPluginException {
      return null;
    }
  }

  /// Requests that CallKit end [callId], or the current call when omitted.
  Future<void> endCall([String? callId]) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('endCall', {'callId': callId});
    } on MissingPluginException {
      // Desktop and web runners intentionally have no CallKit bridge.
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'onCallEnded') return;
    final arguments = Map<Object?, Object?>.from(
      call.arguments as Map? ?? const <Object?, Object?>{},
    );
    final callId = arguments['callId'] as String?;
    if (callId == null || callId.isEmpty) return;
    _hangups.add(
      TauVoiceCallHangup(
        callId: callId,
        source: arguments['source'] as String? ?? 'system',
      ),
    );
  }
}
