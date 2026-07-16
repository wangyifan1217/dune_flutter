import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../auth/auth_session_coordinator.dart';
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
  final ValueNotifier<String> meetingTitle = ValueNotifier<String>('');
  final ValueNotifier<Duration> elapsed = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> interruptionHint = ValueNotifier<String?>(null);

  final List<String> _lines = <String>[];
  Timer? _elapsedTicker;
  Duration _elapsedCommitted = Duration.zero;
  DateTime? _elapsedRunStartedAt;
  StreamSubscription<Map<String, dynamic>>? _recorderEventSub;

  bool get isActive => active.value;

  Future<void> start(AuthSession session, {required String title}) async {
    if (active.value) return;
    meetingTitle.value = title.trim();
    final fresh = AuthSessionCoordinator.instance.resolve(session);
    if (_realtime != null && _realtime!.session.token != fresh.token) {
      await _rtSub?.cancel();
      _rtSub = null;
      await _realtime?.dispose();
      _realtime = null;
    }
    _realtime ??= NativeMeetingRealtimeTranscript(session: fresh);
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
    _recorderEventSub ??=
        NativeAudioRecorder.instance.recorderEvents().listen(_onRecorderEvent);
    paused.value = false;
    active.value = true;
    _elapsedCommitted = Duration.zero;
    elapsed.value = Duration.zero;
    _elapsedRunStartedAt = DateTime.now();
    _startElapsedTicker();
    NativeAudioRecorder.isStartBlocked = () => active.value;
  }

  Future<void> pause() async {
    if (!active.value || paused.value) return;
    await _recording.pause();
    await _realtime?.pause();
    _commitElapsedRun();
    _stopElapsedTicker();
    paused.value = true;
    partial.value = '';
  }

  Future<void> resume() async {
    if (!active.value || !paused.value) return;
    await _recording.resume();
    await _realtime?.resume();
    _elapsedRunStartedAt = DateTime.now();
    _startElapsedTicker();
    paused.value = false;
    interruptionHint.value = null;
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
    _commitElapsedRun();
    _stopElapsedTicker();
    _elapsedRunStartedAt = null;
    interruptionHint.value = null;
    active.value = false;
    paused.value = false;
    NativeAudioRecorder.isStartBlocked = null;
    clearPreview();
    if (path != null && path.isNotEmpty) {
      recordedFilePath.value = path;
    }
    return path;
  }

  /// 清空实时转写预览（新会话或录音结束后调用）。
  void clearPreview() {
    _lines.clear();
    lines.value = const <String>[];
    partial.value = '';
  }

  /// 页面消费掉「已保存文件」后调用，避免重复回填。
  void consumeRecordedFile() {
    recordedFilePath.value = null;
    meetingTitle.value = '';
    elapsed.value = Duration.zero;
    _elapsedCommitted = Duration.zero;
    _elapsedRunStartedAt = null;
  }

  void _startElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshElapsed();
    });
    _refreshElapsed();
  }

  void _stopElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
  }

  void _commitElapsedRun() {
    final startedAt = _elapsedRunStartedAt;
    if (startedAt == null) return;
    final now = DateTime.now();
    if (now.isAfter(startedAt)) {
      _elapsedCommitted += now.difference(startedAt);
    }
    _elapsedRunStartedAt = null;
    _refreshElapsed();
  }

  void _refreshElapsed() {
    var current = _elapsedCommitted;
    final startedAt = _elapsedRunStartedAt;
    if (startedAt != null) {
      final now = DateTime.now();
      if (now.isAfter(startedAt)) {
        current += now.difference(startedAt);
      }
    }
    elapsed.value = current;
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

  void _onRecorderEvent(Map<String, dynamic> event) {
    final kind = (event['kind'] ?? '').toString();
    final reason = (event['reason'] ?? '').toString();
    if (kind == 'paused') {
      if (active.value && !paused.value) {
        interruptionHint.value = _pauseHintForReason(reason);
        unawaited(pause());
      }
      return;
    }
    if (kind == 'interruptionEnded' && active.value && paused.value) {
      interruptionHint.value = '麦克风已可用，可点击继续录音';
    }
  }

  String _pauseHintForReason(String reason) {
    switch (reason) {
      case 'audioFocusLoss':
      case 'audioRecordError':
      case 'audioRecordGone':
      case 'audioRecordSilent':
      case 'audioRecordException':
      case 'routeChange':
        return '麦克风被其他语音软件占用，录音已自动暂停并保存';
      case 'interruption':
      case 'mediaServicesReset':
        return '来电或系统中断，录音已自动暂停并保存';
      default:
        return '麦克风被占用，录音已自动暂停并保存';
    }
  }
}
