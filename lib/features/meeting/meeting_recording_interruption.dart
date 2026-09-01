/// 现场录音被来电/抢麦打断后的文案与状态对齐。
///
/// 系统电话会抢走麦克风，不能边打边录。目标是：已录片段不丢、挂断后续上、
/// 用户始终知道「现在没在录」，避免界面还显示进行中、纪要后半段莫名缺失。
enum MeetingRecorderSyncAction {
  none,

  /// 原生已停、Dart 还以为在录 → 立刻改成系统暂停。
  markPausedByInterruption,

  /// 原生已在录、Dart 还停在暂停 → 跟上原生。
  markResumed,

  /// 仍是系统暂停，应再试自动续录。
  tryAutoResume,

  /// 原生会话没了，不能当还在录。
  markNativeSessionLost,
}

class NativeRecorderSnapshot {
  const NativeRecorderSnapshot({
    required this.isRecording,
    required this.isPaused,
  });

  final bool isRecording;
  final bool isPaused;
}

class MeetingRecordingInterruption {
  const MeetingRecordingInterruption._();

  static const resumeRetryDelays = <Duration>[
    Duration(milliseconds: 600),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  static bool allowsAutoResume(String reason) {
    switch (reason) {
      case 'routeDeviceLost':
      case 'routeChange':
        return false;
      default:
        return true;
    }
  }

  static String hintForReason(String reason) {
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
        return '来电或系统中断，录音已自动暂停；挂断后将自动继续，已录部分已保存';
      default:
        return '录音已自动暂停；恢复后将尝试自动继续，已录部分已保存';
    }
  }

  static String fabLabel({
    required bool paused,
    required bool pausedByInterruption,
    required String elapsedText,
  }) {
    if (!paused) return '录音进行中 $elapsedText';
    if (pausedByInterruption) return '来电已暂停 点此继续';
    return '录音已暂停 $elapsedText';
  }

  static MeetingRecorderSyncAction reconcile({
    required bool dartActive,
    required bool dartPaused,
    required bool pausedByInterruption,
    required NativeRecorderSnapshot native,
  }) {
    if (!dartActive) return MeetingRecorderSyncAction.none;
    if (!native.isRecording) {
      return MeetingRecorderSyncAction.markNativeSessionLost;
    }
    if (!native.isPaused && dartPaused) {
      return MeetingRecorderSyncAction.markResumed;
    }
    if (native.isPaused && !dartPaused) {
      return MeetingRecorderSyncAction.markPausedByInterruption;
    }
    if (native.isPaused && dartPaused && pausedByInterruption) {
      return MeetingRecorderSyncAction.tryAutoResume;
    }
    return MeetingRecorderSyncAction.none;
  }
}
