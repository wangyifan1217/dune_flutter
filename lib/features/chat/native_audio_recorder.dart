import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeRecordedAudio {
  const NativeRecordedAudio({required this.path, required this.durationMs});

  final String path;
  final int durationMs;
}

class NativeAudioRecorder {
  NativeAudioRecorder._();

  static final NativeAudioRecorder instance = NativeAudioRecorder._();
  static const MethodChannel _channel = MethodChannel('dunes/audio_recorder');
  static const EventChannel _streamChannel = EventChannel('dunes/audio_recorder_stream');

  /// 仅 Android/iOS 原生壳实现了 MethodChannel。
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Web / 桌面调试忽略
    }
  }

  Stream<Uint8List> pcmStream() {
    if (!isSupported) return const Stream<Uint8List>.empty();
    return _streamChannel.receiveBroadcastStream().map((event) {
      if (event is Uint8List) return event;
      if (event is ByteData) return event.buffer.asUint8List();
      if (event is List<int>) return Uint8List.fromList(event);
      return Uint8List(0);
    }).where((chunk) => chunk.isNotEmpty);
  }

  Future<NativeRecordedAudio?> stop() async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('stop');
      if (res is! Map) return null;
      final data = Map<String, dynamic>.from(res);
      final path = (data['path'] ?? '').toString();
      if (path.isEmpty) return null;
      return NativeRecordedAudio(
        path: path,
        durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
      );
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Web / 桌面调试忽略
    } on PlatformException {
      // 忽略取消时的平台异常
    }
  }

  Future<bool> status() async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>('status');
      if (res is Map) {
        final data = Map<String, dynamic>.from(res);
        return data['isRecording'] == true;
      }
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
    return false;
  }
}
