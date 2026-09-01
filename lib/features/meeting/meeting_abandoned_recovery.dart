import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import '../shell/dunes_toast.dart';
import 'meeting_abandoned_session.dart';
import 'meeting_live_controller.dart';
import 'meeting_upload_coordinator.dart';

/// 杀进程后把已落盘片段恢复成会议草稿。
class MeetingAbandonedRecovery {
  MeetingAbandonedRecovery._();

  static bool _inFlight = false;

  static Future<void> promptIfNeeded({
    required BuildContext context,
    required AuthSession session,
  }) async {
    if (_inFlight || !NativeAudioRecorder.isSupported) return;
    if (MeetingLiveController.instance.isActive) return;
    _inFlight = true;
    try {
      final peek = await NativeAudioRecorder.instance.peekAbandonedSession();
      if (peek == null || !context.mounted) return;
      final rec = AbandonedMeetingRecording(
        title: peek.title,
        durationMs: peek.durationMs,
        segmentCount: peek.segmentCount,
      );
      final restore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('发现未完成的会议录音'),
          content: Text(
            abandonedMeetingPrompt(rec),
            style: DunesTypography.sans(fontSize: 13.5, height: 1.55),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('放弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('恢复为草稿'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (restore == true) {
        await _restoreAsDraft(context: context, session: session, rec: rec);
      } else {
        await NativeAudioRecorder.instance.discardAbandonedSession();
      }
    } catch (_) {
      // 恢复失败时保留文件，下次启动再问。
    } finally {
      _inFlight = false;
    }
  }

  static Future<void> _restoreAsDraft({
    required BuildContext context,
    required AuthSession session,
    required AbandonedMeetingRecording rec,
  }) async {
    final audio = await NativeAudioRecorder.instance.recoverAbandonedSession();
    if (audio == null || audio.path.isEmpty) {
      if (context.mounted) {
        showDunesToast(context, '没有可恢复的录音文件', kind: DunesToastKind.error);
      }
      return;
    }
    final now = DateTime.now();
    final meetingDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await MeetingUploadCoordinator.instance.enqueue(
      session: session,
      title: rec.displayTitle,
      meetingDate: meetingDate,
      sourceFilePath: audio.path,
      generate: false,
      recordingDurationSeconds: audio.durationMs ~/ 1000,
    );
    if (context.mounted) {
      showDunesToast(context, '已将中断的会议录音恢复为草稿，可在会议列表中查看');
    }
  }
}
