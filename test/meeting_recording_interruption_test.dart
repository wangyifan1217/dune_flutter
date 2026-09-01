import 'package:dunes_app/features/meeting/meeting_recording_interruption.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeetingRecordingInterruption.hintForReason', () {
    test('phone interruption tells user audio is saved', () {
      expect(
        MeetingRecordingInterruption.hintForReason('interruption'),
        contains('已录部分已保存'),
      );
    });

    test('headset unplug does not promise auto resume', () {
      expect(
        MeetingRecordingInterruption.allowsAutoResume('routeDeviceLost'),
        isFalse,
      );
      expect(
        MeetingRecordingInterruption.hintForReason('routeDeviceLost'),
        contains('点击继续'),
      );
    });
  });

  group('MeetingRecordingInterruption.fabLabel', () {
    test('interruption pause is obvious, not "recording"', () {
      expect(
        MeetingRecordingInterruption.fabLabel(
          paused: true,
          pausedByInterruption: true,
          elapsedText: '12:03',
        ),
        '来电已暂停 点此继续',
      );
    });

    test('active recording keeps elapsed', () {
      expect(
        MeetingRecordingInterruption.fabLabel(
          paused: false,
          pausedByInterruption: false,
          elapsedText: '01:20',
        ),
        '录音进行中 01:20',
      );
    });
  });

  group('MeetingRecordingInterruption.reconcile', () {
    const recording = NativeRecorderSnapshot(
      isRecording: true,
      isPaused: false,
    );
    const nativePaused = NativeRecorderSnapshot(
      isRecording: true,
      isPaused: true,
    );
    const dead = NativeRecorderSnapshot(
      isRecording: false,
      isPaused: false,
    );

    test('native paused while dart still recording is the silent-loss bug', () {
      expect(
        MeetingRecordingInterruption.reconcile(
          dartActive: true,
          dartPaused: false,
          pausedByInterruption: false,
          native: nativePaused,
        ),
        MeetingRecorderSyncAction.markPausedByInterruption,
      );
    });

    test('native already resumed while dart still paused', () {
      expect(
        MeetingRecordingInterruption.reconcile(
          dartActive: true,
          dartPaused: true,
          pausedByInterruption: true,
          native: recording,
        ),
        MeetingRecorderSyncAction.markResumed,
      );
    });

    test('both paused by interruption should retry resume', () {
      expect(
        MeetingRecordingInterruption.reconcile(
          dartActive: true,
          dartPaused: true,
          pausedByInterruption: true,
          native: nativePaused,
        ),
        MeetingRecorderSyncAction.tryAutoResume,
      );
    });

    test('native session gone must not stay "recording"', () {
      expect(
        MeetingRecordingInterruption.reconcile(
          dartActive: true,
          dartPaused: false,
          pausedByInterruption: false,
          native: dead,
        ),
        MeetingRecorderSyncAction.markNativeSessionLost,
      );
    });

    test('idle dart does nothing', () {
      expect(
        MeetingRecordingInterruption.reconcile(
          dartActive: false,
          dartPaused: false,
          pausedByInterruption: false,
          native: nativePaused,
        ),
        MeetingRecorderSyncAction.none,
      );
    });
  });
}
