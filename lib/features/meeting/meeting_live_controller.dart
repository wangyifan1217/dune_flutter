import 'dart:async';

import 'package:flutter/widgets.dart';

import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import 'meeting_recording_interruption.dart';
import 'native_meeting_recording_controller.dart';

/// 常驻的现场录音会话控制器。
///
/// 采用策略 B：即便离开「新建会议纪要」页，录音仍继续；重新进入页面
/// 可继续查看/暂停/继续/结束。全局悬浮按钮也依赖 [active] 判定是否显示。
///
/// 现场录音不再连接实时转写（按流式 ASR 计费）。结束后上传音频，再走文件转写生成纪要。
class MeetingLiveController with WidgetsBindingObserver {
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
  bool _observingLifecycle = false;
  int _resumeAttempts = 0;
  String _pauseReason = '';

  bool get isActive => active.value;

  bool get pausedByInterruption => _pausedByInterruption;

  Future<void> start(AuthSession _, {required String title}) async {
    if (active.value) return;
    meetingTitle.value = title.trim();
    lines.value = const <String>[];
    partial.value = '';
    recordedFilePath.value = null;

    _recording.attach();
    _ensureLifecycleObserver();
    await _recording.start(title: meetingTitle.value);
    _recorderEventSub ??=
        NativeAudioRecorder.instance.recorderEvents().listen(_onRecorderEvent);
    paused.value = false;
    active.value = true;
    _pausedByInterruption = false;
    _pauseReason = '';
    _resumeAttempts = 0;
    _cancelAutoResume();
    _elapsedCommitted = Duration.zero;
    elapsed.value = Duration.zero;
    _elapsedRunStartedAt = DateTime.now();
    _startElapsedTicker();
    NativeAudioRecorder.isStartBlocked = () => active.value;
  }

  Future<void> pause({bool fromInterruption = false, String reason = ''}) async {
    if (!active.value || paused.value) {
      if (active.value && paused.value && fromInterruption) {
        _pausedByInterruption =
            MeetingRecordingInterruption.allowsAutoResume(reason);
        _pauseReason = reason;
      }
      return;
    }
    _cancelAutoResume();
    await _recording.pause();
    _applyPausedUi(fromInterruption: fromInterruption, reason: reason);
  }

  Future<void> resume() async {
    if (!active.value || !paused.value) return;
    _cancelAutoResume();
    final ok = await _recording.resume();
    if (!ok) {
      throw Exception('继续录音失败，麦克风可能仍被占用');
    }
    _applyResumedUi();
  }

  /// 结束并保存，返回录音文件路径（可能为空）。
  Future<String?> end() async {
    _cancelAutoResume();
    _removeLifecycleObserver();
    String? path;
    Object? stopError;
    try {
      final audio = await _recording.stop();
      path = audio?.path;
    } catch (e) {
      stopError = e;
    }
    _commitElapsedRun();
    _stopElapsedTicker();
    _elapsedRunStartedAt = null;
    interruptionHint.value = null;
    _pausedByInterruption = false;
    _pauseReason = '';
    _resumeAttempts = 0;
    active.value = false;
    paused.value = false;
    NativeAudioRecorder.isStartBlocked = null;
    clearPreview();
    if (path != null && path.isNotEmpty) {
      recordedFilePath.value = path;
      return path;
    }
    if (stopError != null) {
      throw stopError;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!active.value) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppForegrounded());
    }
  }

  void _ensureLifecycleObserver() {
    if (_observingLifecycle) return;
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  void _removeLifecycleObserver() {
    if (!_observingLifecycle) return;
    WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
  }

  Future<void> _onAppForegrounded() async {
    if (!active.value) return;
    await _syncWithNativeStatus();
    if (_pausedByInterruption) {
      _scheduleAutoResume(resetAttempts: true);
    }
  }

  Future<void> _syncWithNativeStatus() async {
    if (!active.value) return;
    final status = await NativeAudioRecorder.instance.readStatus();
    final native = NativeRecorderSnapshot(
      isRecording: status.isRecording,
      isPaused: status.isPaused,
    );
    final action = MeetingRecordingInterruption.reconcile(
      dartActive: active.value,
      dartPaused: paused.value,
      pausedByInterruption: _pausedByInterruption,
      native: native,
    );
    switch (action) {
      case MeetingRecorderSyncAction.markPausedByInterruption:
        _applyPausedUi(fromInterruption: true, reason: _pauseReason);
        interruptionHint.value = MeetingRecordingInterruption.hintForReason(
          _pauseReason.isEmpty ? 'interruption' : _pauseReason,
        );
        break;
      case MeetingRecorderSyncAction.markResumed:
        _applyResumedUi();
        interruptionHint.value = '已自动继续录音';
        break;
      case MeetingRecorderSyncAction.tryAutoResume:
        _scheduleAutoResume();
        break;
      case MeetingRecorderSyncAction.markNativeSessionLost:
        _applyPausedUi(fromInterruption: true, reason: 'audioRecordGone');
        interruptionHint.value = '录音被系统中断，已录部分已保存，请点击继续录音';
        break;
      case MeetingRecorderSyncAction.none:
        break;
    }
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
        interruptionHint.value =
            MeetingRecordingInterruption.hintForReason(reason);
        unawaited(pause(fromInterruption: true, reason: reason));
      }
      return;
    }
    if (kind == 'resumed') {
      if (active.value && paused.value) {
        _applyResumedUi();
        interruptionHint.value = '已自动继续录音';
      }
      return;
    }
    if (kind == 'interruptionEnded' &&
        active.value &&
        paused.value &&
        _pausedByInterruption) {
      _scheduleAutoResume(resetAttempts: true);
    }
  }

  void _applyPausedUi({required bool fromInterruption, String reason = ''}) {
    _commitElapsedRun();
    _stopElapsedTicker();
    _pausedByInterruption =
        fromInterruption && MeetingRecordingInterruption.allowsAutoResume(reason);
    _pauseReason = reason;
    paused.value = true;
    partial.value = '';
  }

  void _applyResumedUi() {
    _cancelAutoResume();
    _elapsedRunStartedAt ??= DateTime.now();
    _startElapsedTicker();
    _pausedByInterruption = false;
    _pauseReason = '';
    _resumeAttempts = 0;
    paused.value = false;
    interruptionHint.value = null;
  }

  void _scheduleAutoResume({bool resetAttempts = false}) {
    if (!active.value || !paused.value || !_pausedByInterruption) {
      return;
    }
    if (_autoResuming) return;
    if (resetAttempts) _resumeAttempts = 0;
    if (_resumeAttempts >= MeetingRecordingInterruption.resumeRetryDelays.length) {
      interruptionHint.value = '麦克风已可用，自动继续失败，请点击继续录音';
      return;
    }
    interruptionHint.value = '麦克风已恢复，正在自动继续录音…';
    _cancelAutoResume();
    final delay =
        MeetingRecordingInterruption.resumeRetryDelays[_resumeAttempts];
    _autoResumeTimer = Timer(delay, () {
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
      _resumeAttempts += 1;
      if (_resumeAttempts <
          MeetingRecordingInterruption.resumeRetryDelays.length) {
        _scheduleAutoResume();
      } else {
        interruptionHint.value = '麦克风已可用，自动继续失败，请点击继续录音';
      }
    } finally {
      _autoResuming = false;
    }
  }

  void _cancelAutoResume() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
  }
}
