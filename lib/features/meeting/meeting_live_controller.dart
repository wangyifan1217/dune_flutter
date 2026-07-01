import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import 'native_meeting_realtime_models.dart';
import 'native_meeting_realtime_transcript.dart';
import 'native_meeting_recording_controller.dart';

/// 常驻的实时转写会话控制器。
///
/// 采用策略 B：即便离开「新建会议纪要」页，转写与录音仍继续；重新进入页面
/// 可继续查看/暂停/继续/结束。全局悬浮按钮也依赖 [active] 判定是否显示。
class MeetingLiveController {
  MeetingLiveController._();

  static final MeetingLiveController instance = MeetingLiveController._();

  final MeetingRecordingController _recording =
      MeetingRecordingController.instance;
  NativeMeetingRealtimeTranscript? _realtime;
  StreamSubscription<Uint8List>? _pcmSub;
  StreamSubscription<RealtimeTranscriptUpdate>? _rtSub;

  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(const <String>[]);
  final ValueNotifier<String> partial = ValueNotifier<String>('');
  final ValueNotifier<String?> recordedFilePath = ValueNotifier<String?>(null);

  final List<String> _lines = <String>[];

  bool get isActive => active.value;

  Future<void> start(AuthSession session) async {
    if (active.value) return;
    _realtime ??= NativeMeetingRealtimeTranscript(session: session);
    _rtSub ??= _realtime!.updates.listen(_onUpdate);
    _lines.clear();
    lines.value = const <String>[];
    partial.value = '';
    recordedFilePath.value = null;

    await _realtime!.connect();
    await _pcmSub?.cancel();
    _pcmSub = NativeAudioRecorder.instance.pcmStream().listen((chunk) {
      _realtime?.sendAudioChunk(chunk);
    });
    _recording.attach();
    await _recording.start();
    paused.value = false;
    active.value = true;
  }

  Future<void> pause() async {
    if (!active.value) return;
    await _realtime?.pause();
    paused.value = true;
    partial.value = '';
  }

  Future<void> resume() async {
    if (!active.value) return;
    await _realtime?.resume();
    paused.value = false;
  }

  /// 结束并保存，返回录音文件路径（可能为空）。
  Future<String?> end() async {
    String? path;
    try {
      final audio = await _recording.stop();
      path = audio?.path;
    } catch (_) {
      // Stop failures shouldn't block teardown.
    }
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _realtime?.stop();
    } catch (_) {}
    active.value = false;
    paused.value = false;
    partial.value = '';
    if (path != null && path.isNotEmpty) {
      recordedFilePath.value = path;
    }
    return path;
  }

  /// 页面消费掉「已保存文件」后调用，避免重复回填。
  void consumeRecordedFile() {
    recordedFilePath.value = null;
  }

  void _onUpdate(RealtimeTranscriptUpdate update) {
    if (update.isFinal) {
      partial.value = '';
      final text = update.text;
      final isStatusLine = text.startsWith('[状态]') ||
          text.startsWith('[错误]') ||
          text.startsWith('已连接');
      if (!isStatusLine && _lines.isNotEmpty && _lines.first == text) {
        return;
      }
      _lines.insert(0, text);
      lines.value = List<String>.unmodifiable(_lines);
    } else {
      partial.value = update.text;
    }
  }
}
