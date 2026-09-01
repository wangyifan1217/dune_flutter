import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 麦克风已被会议实时录音占用。
class NativeAudioRecorderBusyException implements Exception {
  const NativeAudioRecorderBusyException([this.message = '会议录音进行中，暂无法使用麦克风']);

  final String message;

  @override
  String toString() => message;
}

class NativeRecordedAudio {
  const NativeRecordedAudio({required this.path, required this.durationMs});

  final String path;
  final int durationMs;
}

class AbandonedRecorderSession {
  const AbandonedRecorderSession({
    required this.title,
    required this.durationMs,
    required this.segmentCount,
  });

  final String title;
  final int durationMs;
  final int segmentCount;
}

class NativeRecorderStatus {
  const NativeRecorderStatus({
    required this.isRecording,
    required this.isPaused,
  });

  final bool isRecording;
  final bool isPaused;
}

class NativeAudioRecorder {
  NativeAudioRecorder._();

  static final NativeAudioRecorder instance = NativeAudioRecorder._();
  static const MethodChannel _channel = MethodChannel('dunes/audio_recorder');
  static const EventChannel _streamChannel = EventChannel('dunes/audio_recorder_stream');
  static const EventChannel _eventsChannel = EventChannel('dunes/audio_recorder_events');

  /// 由会议录音模块注册：返回 true 时拒绝其它入口占用麦克风。
  static bool Function()? isStartBlocked;

  /// 仅 Android/iOS 原生壳实现了 MethodChannel。
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start({
    String title = '',
    bool persistSession = false,
  }) async {
    if (!isSupported) return;
    if (isStartBlocked?.call() == true) {
      throw const NativeAudioRecorderBusyException(
        '会议录音进行中，暂无法发送语音',
      );
    }
    try {
      await _channel.invokeMethod<void>('start', <String, dynamic>{
        'title': title,
        'persistSession': persistSession,
      });
    } on MissingPluginException {
      // Web / 桌面调试忽略
    }
  }

  Future<AbandonedRecorderSession?> peekAbandonedSession() async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('abandonedSession');
      if (res is! Map) return null;
      final data = Map<String, dynamic>.from(res);
      final durationMs = (data['durationMs'] as num?)?.toInt() ?? 0;
      final segmentCount = (data['segmentCount'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0 && segmentCount <= 0) return null;
      return AbandonedRecorderSession(
        title: (data['title'] ?? '').toString(),
        durationMs: durationMs,
        segmentCount: segmentCount,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<NativeRecordedAudio?> recoverAbandonedSession() async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('recoverAbandonedSession');
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
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '恢复录音失败');
    }
  }

  Future<void> discardAbandonedSession() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('discardAbandonedSession');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  Future<bool> pause() async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>('pause');
      return res != false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> resume() async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<dynamic>('resume');
      return res != false;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '继续录音失败');
    } on MissingPluginException {
      return false;
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

  /// 原生录音事件：来电/系统中断时自动暂停、中断结束可继续。
  Stream<Map<String, dynamic>> recorderEvents() {
    if (!isSupported) return const Stream<Map<String, dynamic>>.empty();
    return _eventsChannel.receiveBroadcastStream().map((event) {
      if (event is Map) return Map<String, dynamic>.from(event);
      return const <String, dynamic>{};
    }).where((event) => event.isNotEmpty);
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
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '录音保存失败');
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
    final detail = await readStatus();
    return detail.isRecording;
  }

  Future<NativeRecorderStatus> readStatus() async {
    if (!isSupported) {
      return const NativeRecorderStatus(isRecording: false, isPaused: false);
    }
    try {
      final res = await _channel.invokeMethod<dynamic>('status');
      if (res is Map) {
        final data = Map<String, dynamic>.from(res);
        return NativeRecorderStatus(
          isRecording: data['isRecording'] == true,
          isPaused: data['isPaused'] == true,
        );
      }
    } on MissingPluginException {
      return const NativeRecorderStatus(isRecording: false, isPaused: false);
    } on PlatformException {
      return const NativeRecorderStatus(isRecording: false, isPaused: false);
    }
    return const NativeRecorderStatus(isRecording: false, isPaused: false);
  }
}
