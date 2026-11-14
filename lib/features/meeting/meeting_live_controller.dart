import 'dart:async';

import 'package:flutter/foundation.dart';
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
  final ValueNotifier<bool> saveFailed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> recovering = ValueNotifier<bool>(false);
  final ValueNotifier<int> openRequests = ValueNotifier<int>(0);
  final ValueNotifier<List<String>> lines = ValueNotifier<List<String>>(
    const <String>[],
  );
  final ValueNotifier<String> partial = ValueNotifier<String>('');
  final ValueNotifier<String?> recordedFilePath = ValueNotifier<String?>(null);
  final ValueNotifier<String> meetingTitle = ValueNotifier<String>('');
  final ValueNotifier<Duration> elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );
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
  Future<String?>? _ending;
  Future<void>? _foregroundSync;
  Future<void>? _resuming;
  Completer<void>? _recoveryDone;
  bool _userPaused = false;
  int _sessionGeneration = 0;
  int _resumeGeneration = 0;
  int _autoResumeRevision = 0;

  int get autoResumeRevision => _autoResumeRevision;
  bool get userPaused => _userPaused;
  bool get isStopping => _ending != null;

  bool get isActive => active.value;

  bool get pausedByInterruption => _pausedByInterruption;

  Future<void> start(AuthSession _, {required String title}) async {
    if (active.value) return;
    _sessionGeneration++;
    _resumeGeneration++;
    _userPaused = false;
    _finishAutoResume();
    meetingTitle.value = title.trim();
    lines.value = const <String>[];
    partial.value = '';
    recordedFilePath.value = null;

    _recording.attach();
    _ensureLifecycleObserver();
    await _recording.start(title: meetingTitle.value);
    _recorderEventSub ??= NativeAudioRecorder.instance.recorderEvents().listen(
      _onRecorderEvent,
    );
    paused.value = false;
    saveFailed.value = false;
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

  Future<void> pause({
    bool fromInterruption = false,
    String reason = '',
  }) async {
    if (_ending != null || saveFailed.value) return;
    if (!fromInterruption) {
      _userPaused = true;
      _resumeGeneration++;
      _cancelAutoResume();
      _finishAutoResume();
      // A user pause must win over a resume already crossing the platform channel.
      try {
        await _resuming;
      } catch (_) {}
      if (!active.value || _ending != null) return;
      await _recording.pause();
      _applyPausedUi(fromInterruption: false);
      return;
    }
    if (_userPaused) return;
    if (!active.value || paused.value) {
      if (active.value && paused.value && fromInterruption) {
        _pausedByInterruption = MeetingRecordingInterruption.allowsAutoResume(
          reason,
        );
        _pauseReason = reason;
      }
      return;
    }
    _cancelAutoResume();
    await _recording.pause();
    _applyPausedUi(fromInterruption: fromInterruption, reason: reason);
  }

  Future<void> resume({bool automatic = false}) {
    if (_resuming != null) return _resuming!;
    if (!automatic) {
      _cancelAutoResume();
      _finishAutoResume();
    }
    final operation = _resume();
    _resuming = operation;
    return operation.whenComplete(() => _resuming = null);
  }

  Future<void> _resume() async {
    if (_ending != null || saveFailed.value) return;
    if (!active.value || !paused.value) return;
    _userPaused = false;
    final generation = _resumeGeneration;
    _cancelAutoResume();
    final before = await NativeAudioRecorder.instance.readStatus();
    if (generation != _resumeGeneration || _ending != null) return;
    final ok = await _recording.resume();
    if (!ok) {
      throw Exception('继续录音失败，麦克风可能仍被占用');
    }
    if (generation != _resumeGeneration || _ending != null) return;
    // Only report success after the native recorder is running and writing again.
    final verified = await _verifyCapture(before);
    if (generation != _resumeGeneration || _ending != null || !active.value) {
      return;
    }
    if (!verified) {
      await _recording.pause();
      throw Exception('尚未检测到录音恢复，请稍后重试');
    }
    _applyResumedUi();
  }

  Future<bool> _verifyCapture(NativeRecorderStatus before) async {
    final sessionGeneration = _sessionGeneration;
    var baselineBytes = before.capturedBytes;
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final status = await NativeAudioRecorder.instance.readStatus();
      if (sessionGeneration != _sessionGeneration ||
          !active.value ||
          _ending != null ||
          _userPaused) {
        return false;
      }
      if (!status.available ||
          !status.isRecording ||
          status.isPaused ||
          status.captureSilenced) {
        return false;
      }
      // Older native shells have no byte counter; still require a fresh native status.
      if (status.capturedBytes == null ||
          (baselineBytes != null && status.capturedBytes! > baselineBytes)) {
        _alignElapsed(status);
        return true;
      }
      baselineBytes ??= status.capturedBytes;
    }
    return false;
  }

  void _alignElapsed(NativeRecorderStatus status) {
    final duration = status.durationMs;
    if (duration == null) return;
    _elapsedCommitted = Duration(milliseconds: duration);
    _elapsedRunStartedAt = status.isPaused ? null : DateTime.now();
    _refreshElapsed();
  }

  /// 结束并保存，返回录音文件路径（可能为空）。
  Future<String?> end() {
    final pending = _ending;
    if (pending != null) return pending;
    final operation = _endAndRecover();
    _ending = operation;
    return operation.whenComplete(() => _ending = null);
  }

  Future<String?> _endAndRecover() async {
    final hadSession = active.value || saveFailed.value;
    _resumeGeneration++;
    _cancelAutoResume();
    _finishAutoResume();
    _removeLifecycleObserver();
    String? path;
    Object? stopError;
    try {
      try {
        await _resuming;
      } catch (_) {}
      final audio = await _recording.stop();
      path = audio?.path;
    } catch (e) {
      stopError = e;
    }
    // Android preserves a recovery index when stopping fails. Try it before
    // discarding the live UI; iOS keeps its existing stop/return contract.
    final android =
        hadSession &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
    if ((path == null || path.isEmpty) && android) {
      try {
        final status = await NativeAudioRecorder.instance.readStatus();
        if (!status.isRecording) {
          final recovered = await NativeAudioRecorder.instance
              .recoverAbandonedSession();
          path = recovered?.path;
        }
      } catch (e) {
        stopError ??= e;
      }
    }
    _commitElapsedRun();
    _stopElapsedTicker();
    _elapsedRunStartedAt = null;
    _pausedByInterruption = false;
    _pauseReason = '';
    _resumeAttempts = 0;
    if ((path == null || path.isEmpty) && android) {
      saveFailed.value = true;
      active.value = true;
      paused.value = true;
      NativeAudioRecorder.isStartBlocked = () => active.value;
      interruptionHint.value = '保存未完成，请重试保存；已有录音文件会保留';
      throw stopError ?? Exception('未取得有效录音，请重试保存或放弃此录音');
    }
    _finishLiveSession();
    if (path != null && path.isNotEmpty) {
      recordedFilePath.value = path;
      return path;
    }
    if (stopError != null) {
      throw stopError;
    }
    return path;
  }

  Future<void> discardFailedRecording() async {
    if (!saveFailed.value || _ending != null) return;
    await _recording.cancel();
    await NativeAudioRecorder.instance.discardAbandonedSession();
    _finishLiveSession();
    consumeRecordedFile();
  }

  void _finishLiveSession() {
    _sessionGeneration++;
    _resumeGeneration++;
    _cancelAutoResume();
    _finishAutoResume();
    _userPaused = false;
    _removeLifecycleObserver();
    final subscription = _recorderEventSub;
    _recorderEventSub = null;
    if (subscription != null) unawaited(subscription.cancel());
    saveFailed.value = false;
    interruptionHint.value = null;
    active.value = false;
    paused.value = false;
    NativeAudioRecorder.isStartBlocked = null;
    _recording.detach();
    clearPreview();
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
      unawaited(syncOnForeground());
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

  Future<void> syncOnForeground() {
    if (_foregroundSync != null) return _foregroundSync!;
    final operation = _onAppForegrounded();
    _foregroundSync = operation;
    return operation.whenComplete(() => _foregroundSync = null);
  }

  Future<void> _onAppForegrounded() async {
    if (!active.value || _ending != null || saveFailed.value) return;
    final generation = _sessionGeneration;
    try {
      await _syncWithNativeStatus();
    } catch (_) {
      if (generation != _sessionGeneration ||
          !active.value ||
          _ending != null ||
          _userPaused) {
        return;
      }
      _applyPausedUi(fromInterruption: true, reason: 'statusUnavailable');
      interruptionHint.value = '暂时无法确认录音状态，正在尝试恢复';
    }
    if (generation != _sessionGeneration || !active.value || _ending != null) {
      return;
    }
    if (_pausedByInterruption && !_userPaused) {
      _scheduleAutoResume(resetAttempts: true);
    }
    await _recoveryDone?.future;
  }

  Future<void> _syncWithNativeStatus() async {
    if (!active.value) return;
    final generation = _sessionGeneration;
    final status = await NativeAudioRecorder.instance.readStatus();
    if (generation != _sessionGeneration || !active.value || _ending != null) {
      return;
    }
    if (!status.available) {
      _applyPausedUi(fromInterruption: true, reason: 'statusUnavailable');
      interruptionHint.value = '暂时无法确认录音状态，正在尝试恢复';
      return;
    }
    _alignElapsed(status);
    if (_userPaused) {
      if (status.isRecording && !status.isPaused) await _recording.pause();
      return;
    }
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
        _applyPausedUi(
          fromInterruption: true,
          reason: status.pauseReason.isEmpty
              ? _pauseReason
              : status.pauseReason,
        );
        interruptionHint.value = MeetingRecordingInterruption.hintForReason(
          _pauseReason.isEmpty ? 'interruption' : _pauseReason,
        );
        break;
      case MeetingRecorderSyncAction.markResumed:
        if (await _verifyCapture(status)) {
          _applyResumedUi();
          _autoResumeRevision++;
          interruptionHint.value = '已自动继续录音';
        }
        break;
      case MeetingRecorderSyncAction.tryAutoResume:
        _scheduleAutoResume();
        break;
      case MeetingRecorderSyncAction.markNativeSessionLost:
        _applyPausedUi(fromInterruption: false, reason: 'nativeSessionLost');
        saveFailed.value = true;
        interruptionHint.value = '录音会话已中断，请进入会议恢复并保存已有录音';
        break;
      case MeetingRecorderSyncAction.none:
        if (!paused.value && !await _verifyCapture(status)) {
          if (generation != _sessionGeneration ||
              !active.value ||
              _ending != null ||
              _userPaused) {
            return;
          }
          await _recording.pause();
          _applyPausedUi(fromInterruption: true, reason: 'audioRecordSilent');
        }
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
    if (_ending != null || saveFailed.value) return;
    final kind = (event['kind'] ?? '').toString();
    final reason = (event['reason'] ?? '').toString();
    if (kind == 'openMeeting') {
      openRequests.value++;
      return;
    }
    if (kind == 'paused') {
      if (active.value && !_userPaused) {
        interruptionHint.value = MeetingRecordingInterruption.hintForReason(
          reason,
        );
        // Native has already paused; issuing a second pause can race its recovery.
        _applyPausedUi(fromInterruption: true, reason: reason);
      }
      return;
    }
    if (kind == 'resumed') {
      if (active.value) unawaited(syncOnForeground());
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
        fromInterruption &&
        MeetingRecordingInterruption.allowsAutoResume(reason);
    _pauseReason = reason;
    if (!_pausedByInterruption) {
      _cancelAutoResume();
      _finishAutoResume();
    }
    paused.value = true;
    partial.value = '';
  }

  void _applyResumedUi() {
    _cancelAutoResume();
    _finishAutoResume();
    _elapsedRunStartedAt ??= DateTime.now();
    _startElapsedTicker();
    _pausedByInterruption = false;
    _pauseReason = '';
    _resumeAttempts = 0;
    paused.value = false;
    interruptionHint.value = null;
  }

  void _scheduleAutoResume({bool resetAttempts = false}) {
    if (!active.value ||
        !paused.value ||
        !_pausedByInterruption ||
        _userPaused ||
        _ending != null ||
        saveFailed.value) {
      return;
    }
    if (_autoResuming) return;
    if (resetAttempts) _resumeAttempts = 0;
    if (_resumeAttempts >=
        MeetingRecordingInterruption.resumeRetryDelays.length) {
      interruptionHint.value = '自动继续录音失败，请进入会议检查并重试';
      _finishAutoResume();
      return;
    }
    _recoveryDone ??= Completer<void>();
    recovering.value = true;
    interruptionHint.value = '正在尝试恢复会议录音…';
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
      _finishAutoResume();
      return;
    }
    _autoResuming = true;
    var retry = false;
    try {
      await resume(automatic: true);
      if (active.value && !paused.value && _ending == null && !_userPaused) {
        _autoResumeRevision++;
        interruptionHint.value = '已自动继续录音';
      }
    } catch (_) {
      _resumeAttempts += 1;
      retry =
          active.value && paused.value && _pausedByInterruption && !_userPaused;
    } finally {
      _autoResuming = false;
    }
    // Release the in-flight guard before scheduling the next attempt.
    if (retry) {
      _scheduleAutoResume();
    } else {
      _finishAutoResume();
    }
  }

  void _finishAutoResume() {
    recovering.value = false;
    final pending = _recoveryDone;
    _recoveryDone = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _cancelAutoResume() {
    _autoResumeTimer?.cancel();
    _autoResumeTimer = null;
  }
}
