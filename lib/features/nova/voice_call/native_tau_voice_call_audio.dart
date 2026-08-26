import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/util/native_permissions.dart';
import '../../chat/native_audio_recorder.dart';

/// PCM capture dedicated to the τ phone experience.
///
/// The channel is intentionally independent of `dunes/audio_recorder`: it
/// neither writes an audio file nor starts the meeting recording service.
class NativeTauVoiceCallAudio {
  NativeTauVoiceCallAudio._();

  static final NativeTauVoiceCallAudio instance = NativeTauVoiceCallAudio._();

  static const MethodChannel _channel = MethodChannel('dunes/voice_call');
  static const EventChannel _pcmChannel = EventChannel('dunes/voice_call_pcm');
  static const EventChannel _eventsChannel = EventChannel(
    'dunes/voice_call_events',
  );
  final AudioRecorder _desktopRecorder = AudioRecorder();
  final StreamController<Uint8List> _desktopPcm =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<Uint8List>? _desktopCapture;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _usesDesktopRecorder =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Mono, signed 16-bit little-endian PCM at 16 kHz.
  Stream<Uint8List> pcmStream() {
    if (!isSupported) return const Stream<Uint8List>.empty();
    if (_usesDesktopRecorder) return _desktopPcm.stream;
    return _pcmChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Uint8List) return event;
          if (event is ByteData) return event.buffer.asUint8List();
          if (event is List<int>) return Uint8List.fromList(event);
          return Uint8List(0);
        })
        .where((chunk) => chunk.isNotEmpty);
  }

  /// System-level lifecycle events, including the Android notification hangup.
  ///
  /// Android emits hangup from the foreground notification. iOS registers the
  /// same channel as a no-op; hangup arrives through CallKit instead.
  Stream<Map<String, dynamic>> events() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _eventsChannel
        .receiveBroadcastStream()
        .map((event) {
          if (event is Map) return Map<String, dynamic>.from(event);
          return const <String, dynamic>{};
        })
        .where((event) => event.isNotEmpty);
  }

  Future<void> start() async {
    if (!isSupported) return;
    if (NativeAudioRecorder.isStartBlocked?.call() == true) {
      throw const NativeAudioRecorderBusyException(
        '会议录音进行中，暂无法使用 τ 电话',
      );
    }
    if (_usesDesktopRecorder) {
      if (!await _desktopRecorder.hasPermission()) {
        throw Exception('未授予麦克风权限');
      }
      if (_desktopCapture != null) return;
      final stream = await _desktopRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _desktopCapture = stream.listen(
        _desktopPcm.add,
        onError: _desktopPcm.addError,
      );
      return;
    }
    try {
      await _channel.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      if (e.code == 'VOICE_CALL_PERMISSION_DENIED') {
        throw Exception(
          microphonePermissionHint(await Permission.microphone.status),
        );
      }
      throw Exception(e.message ?? '无法启动 τ 电话音频');
    } on MissingPluginException {
      // Desktop and web builds intentionally have no native call channel.
    }
  }

  Future<void> playWav(Uint8List bytes) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('play', bytes);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '无法播放语音');
    } on MissingPluginException {
      // Desktop and web builds intentionally have no native call channel.
    }
  }

  Future<void> stopPlayback() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopPlayback');
    } on MissingPluginException {
      // Desktop and web builds intentionally have no native call channel.
    }
  }

  /// Stops capture and releases the voice communication audio route.
  Future<void> stop() async {
    if (!isSupported) return;
    if (_usesDesktopRecorder) {
      await _desktopCapture?.cancel();
      _desktopCapture = null;
      await _desktopRecorder.stop();
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '无法停止 τ 电话音频');
    } on MissingPluginException {
      // Desktop and web builds intentionally have no native call channel.
    }
  }

  /// Stops capture and discards any in-flight PCM at the native boundary.
  Future<void> cancel() async {
    if (!isSupported) return;
    if (_usesDesktopRecorder) {
      await _desktopCapture?.cancel();
      _desktopCapture = null;
      await _desktopRecorder.cancel();
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Desktop and web builds intentionally have no native call channel.
    } on PlatformException {
      // Cancellation must remain safe during route/interruption teardown.
    }
  }
}
