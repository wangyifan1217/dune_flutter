import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import 'native_meeting_recording_controller.dart';

/// 常驻的现场录音会话控制器。
///
/// 采用策略 B：即便离开「新建会议纪要」页，录音仍继续；重新进入页面
/// 可继续查看/暂停/继续/结束。全局悬浮按钮也依赖 [active] 判定是否显示。
///
/// 现场录音不再连接实时转写（按流式 ASR 计费）。结束后上传音频，再走文件转写生成纪要。
class MeetingLiveController {
  MeetingLiveController._();

  static final MeetingLiveController instance = MeetingLiveController._();

  final MeetingRecordingController _recording =
      MeetingRecordingController.instance;

  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(const <String>[]);
  final ValueNotifier<String> partial = ValueNotifier<String>('');
  final ValueNotifier<String?> recordedFilePath = ValueNotifier<String?>(null);
  final ValueNotifier<String> meetingTitle = ValueNotifier<String>('');
  final ValueNotifier<Duration> elapsed = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<String?> interruptionHint = ValueNotifier<String?>(null);

  Timer? _elapsedTicker;
  Timer? _autoResumeTimer;
  Duration _elapsedCommitted = Duration.zero;
  DateTime? _elapsedRunStartedAt;
  StreamSubscription<Map<String, dynamic>>? _recorderEventSub;

  /// 仅系统中断（来电/其他语音软件）触发的暂停才会在恢复后自动续录。
  bool _pausedByInterruption = false;
  bool _autoResuming = false;

  bool get isActive => active.value;

  Future<void> start(AuthSession _, {required String title}) async {
    if (active.value) return;
    meetingTitle.value = title.trim();
    lines.value = const <String>[];
    partial.value = '';
    recordedFilePath.value = null;

    _recording.attach();
    await _recording.start();
    _recorderEventSub ??=
        NativeAudioRecorder.instance.recorderEvents().listen(_onRecorderEvent);
    paused.value = false;
    active.value = true;
    _pausedByInterruption = false;
    _cancelAutoResume();
    _elapsedCommitted = Duration.zero;
    elapsed.value = Duration.zero;
    _elapsedRunStartedAt = DateTime.now();
    _startElapsedTicker();
    NativeAudioRecorder.isStartBlocked = () => active.value;
  }

  Future<void> pause({bool fromInterruption = false}) async {
    if (!active.value || paused.value) return;
    _cancelAutoResume();
    await _recording.pause();
    _commitElapsedRun();
    _stopElapsedTicker();
    _pausedByInterruption = fromInterruption;
    paused.value = true;
    partial.value = '';
  }

  Future<void> resume() async {
    if (!active.value || !paused.value) return;
    _cancelAutoResume();
    await _recording.resume();
    _elapsedRunStartedAt = DateTime.now();
    _startElapsedTicker();
    _pausedByInterruption = false;
    paused.value = false;
    interruptionHint.value = null;
  }

  /// 结束并保存，返回录音文件路径（可能为空）。
  Future<String?> end() async {
    _cancelAutoResume();
    String? path;
    try {
      final audio = await _recording.stop();
      path = audio?.path;
    } catch (_) {
      // Stop failures shouldn't block teardown.
    }
    _commitElapsedRun();
    _stopElapsedTicker();
    _elapsedRunStartedAt = null;
    interruptionHint.value = null;
    _pausedByInterruption = false;
    active.value = false;
    paused.value = false;
    NativeAudioRecorder.isStartBlocked = null;
    clearPreview();
    if (path != null && path.isNotEmpty) {
      recordedFilePath.value = path;
    }
    return path;
  }

  /// 清空现场预览缓存（新会话或录音结束后调用）。
  void clearPreview() {
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

  void _onRecorderEvent(Map<String, dynamic> event) {
    final kind = (event['kind'] ?? '').toString();
    final reason = (event['reason'] ?? '').toString();
    if (kind == 'paused') {
      if (active.value && !paused.value) {
        interruptionHint.value = _pauseHintForReason(reason);
        unawaited(pause(fromInterruption: true));
      }
      return;
    }
    if (kind == 'interruptionEnded' &&
        active.value &&
        paused.value &&
        _pausedByInterruption) {
      _scheduleAutoResume();
    }
  }

  void _scheduleAutoResume() {
    if (_autoResuming || !active.value || !paused.value || !_pausedByInterruption) {
      return;
    }
    interruptionHint.value = '麦克风已恢复，正在自动继续录音…';
    _cancelAutoResume();
    // 稍等会话稳定，再尝试续录（失败则提示手动继续）。
    _autoResumeTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_tryAutoResume());
    });
  }

  Future<void> _tryAutoResume() async {
    if (_autoResuming ||
        !active.value ||
        !paused.value ||
        !_pausedByInterruption) {
      return;
    }
    _autoResuming = true;
    try {
      await resume();
      interruptionHint.value = '已自动继续录音';
    } catch (_) {
      interruptionHint.value = '麦克风已可用，自动继续失败，请点击继续录音';
    } finally {
      _autoResuming = false;
    }
  }

  void _cancelAutoResume() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
  }

  String _pauseHintForReason(String reason) {
    switch (reason) {
      case 'audioFocusLoss':
      case 'audioRecordError':
      case 'audioRecordGone':
      case 'audioRecordSilent':
      case 'audioRecordException':
        return '麦克风被其他语音软件占用，录音已自动暂停；对方结束后将自动继续';
      case 'routeDeviceLost':
      case 'routeChange':
        return '音频设备已断开，录音已自动暂停；请重新连接后点击继续';
      case 'interruption':
      case 'mediaServicesReset':
        return '来电或系统中断，录音已自动暂停；结束后将自动继续';
      default:
        return '录音已自动暂停；恢复后将尝试自动继续';
    }
  }
}
