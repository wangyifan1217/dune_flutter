import 'dart:async';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/native_audio_recorder.dart';
import 'package:dunes_app/features/meeting/meeting_live_controller.dart';
import 'package:dunes_app/features/meeting/native_meeting_recording_controller.dart';
import 'package:dunes_app/features/meeting/native_meeting_create_page.dart';
import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recorder = MethodChannel('dunes/audio_recorder');
  const events = MethodChannel('dunes/audio_recorder_events');
  const session = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'test',
    apiBase: 'https://example.test/api/v1',
    roles: [],
  );
  final live = MeetingLiveController.instance;
  final calls = <String>[];
  Map<String, Object>? stopResult;
  Map<String, Object>? recoveryResult;
  bool stopThrows = false;
  Completer<Map<String, Object>?>? pendingStop;
  Map<String, dynamic>? startArguments;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    stopThrows = false;
    stopResult = null;
    recoveryResult = null;
    pendingStop = null;
    startArguments = null;
    live.consumeRecordedFile();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'start':
              startArguments = Map<String, dynamic>.from(call.arguments as Map);
              return true;
            case 'stop':
              if (pendingStop != null) return pendingStop!.future;
              if (stopThrows) {
                throw PlatformException(
                  code: 'AUDIO_STOP_FAILED',
                  message: 'codec finalization failed',
                );
              }
              return stopResult;
            case 'status':
              return {'isRecording': false, 'isPaused': false};
            case 'recoverAbandonedSession':
              return recoveryResult;
            default:
              return true;
          }
        });
  });
  tearDown(() async {
    if (live.saveFailed.value) await live.discardFailedRecording();
    if (live.active.value) {
      stopThrows = false;
      pendingStop = null;
      stopResult = {'path': '/recording/cleanup.m4a', 'durationMs': 1000};
      await live.end();
    }
    live.consumeRecordedFile();
    MeetingRecordingController.instance.detach();
    NativeAudioRecorder.isStartBlocked = null;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  test(
    'chat voice keeps non-meeting arguments and the original AAC response contract',
    () async {
      stopResult = {'path': '/recording/chat.m4a', 'durationMs': 1800};
      await NativeAudioRecorder.instance.start();
      expect(startArguments?['persistSession'], isFalse);
      final audio = await NativeAudioRecorder.instance.stop();
      expect(audio?.path, '/recording/chat.m4a');
      expect(audio?.durationMs, 1800);
      expect(calls, ['start', 'stop']);
      expect(live.active.value, isFalse);
    },
  );

  test(
    'normal short recording keeps the existing path contract without recovery',
    () async {
      stopResult = {'path': '/recording/short.m4a', 'durationMs': 250};
      await live.start(session, title: 'short');
      expect(await live.end(), '/recording/short.m4a');
      expect(live.recordedFilePath.value, '/recording/short.m4a');
      expect(live.active.value, isFalse);
      expect(live.saveFailed.value, isFalse);
      expect(
        MeetingRecordingController.instance.state.value,
        MeetingRecordingState.idle,
      );
      expect(calls, ['start', 'stop']);
    },
  );

  for (final throws in [false, true]) {
    test(
      'Android recovers WAV after native stop ${throws ? 'exception' : 'empty result'}',
      () async {
        stopThrows = throws;
        recoveryResult = {
          'path': '/recording/recovered.wav',
          'durationMs': 3000,
        };
        await live.start(session, title: 'recovery');
        expect(await live.end(), '/recording/recovered.wav');
        expect(live.active.value, isFalse);
        expect(live.saveFailed.value, isFalse);
        expect(live.recordedFilePath.value, '/recording/recovered.wav');
        expect(calls, ['start', 'stop', 'status', 'recoverAbandonedSession']);
        expect(
          MeetingRecordingController.instance.state.value,
          MeetingRecordingState.idle,
        );
      },
    );
  }

  test(
    'failed stop preserves session for retry and blocks a new recorder from replacing files',
    () async {
      stopThrows = true;
      await live.start(session, title: 'keep this meeting');
      await expectLater(live.end(), throwsException);
      expect(live.active.value, isTrue);
      expect(live.paused.value, isTrue);
      expect(live.saveFailed.value, isTrue);
      expect(live.meetingTitle.value, 'keep this meeting');
      expect(
        MeetingRecordingController.instance.state.value,
        MeetingRecordingState.idle,
      );
      await expectLater(
        NativeAudioRecorder.instance.start(),
        throwsA(isA<NativeAudioRecorderBusyException>()),
      );
      await live.resume();
      expect(calls.where((call) => call == 'resume'), isEmpty);

      stopThrows = false;
      stopResult = {'path': '/recording/retried.wav', 'durationMs': 3000};
      expect(await live.end(), '/recording/retried.wav');
      expect(live.active.value, isFalse);
      expect(live.saveFailed.value, isFalse);
      expect(live.meetingTitle.value, 'keep this meeting');
      expect(calls.where((call) => call == 'start').length, 1);
    },
  );

  test(
    'explicit discard releases the failed meeting without uploading',
    () async {
      await live.start(session, title: 'discard');
      await expectLater(live.end(), throwsException);
      await live.discardFailedRecording();
      expect(live.active.value, isFalse);
      expect(live.saveFailed.value, isFalse);
      expect(live.recordedFilePath.value, isNull);
      expect(live.meetingTitle.value, isEmpty);
      expect(calls, containsAllInOrder(['cancel', 'discardAbandonedSession']));
      expect(NativeAudioRecorder.isStartBlocked, isNull);
    },
  );

  test(
    'concurrent end requests stop once and return the same recording',
    () async {
      pendingStop = Completer<Map<String, Object>?>();
      await live.start(session, title: 'double tap');
      final first = live.end();
      final second = live.end();
      pendingStop!.complete({'path': '/recording/one.m4a', 'durationMs': 1000});
      expect(await first, '/recording/one.m4a');
      expect(await second, '/recording/one.m4a');
      expect(calls.where((call) => call == 'stop').length, 1);
    },
  );

  test(
    'iOS stop error retains existing behavior and does not call Android recovery',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      stopThrows = true;
      await live.start(session, title: 'iOS');
      await expectLater(live.end(), throwsException);
      expect(live.active.value, isFalse);
      expect(live.saveFailed.value, isFalse);
      expect(calls, ['start', 'stop']);
      expect(
        MeetingRecordingController.instance.state.value,
        MeetingRecordingState.idle,
      );
    },
  );

  testWidgets('failed meeting offers retry and confirmed discard in the page', (
    tester,
  ) async {
    stopThrows = true;
    await live.start(session, title: 'failed meeting');
    await expectLater(live.end(), throwsException);
    final navigation = DunesNavigationController();
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: NativeMeetingCreatePage(
          session: session,
          navigation: navigation,
          onBack: () {},
          onCreated: (id, {required isDraft}) =>
              fail('failed stop must not upload'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.text('放弃录音'), findsOneWidget);
    await tester.ensureVisible(find.text('放弃录音'));
    await tester.tap(find.text('放弃录音'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('放弃这次录音？'), findsOneWidget);
    expect(live.saveFailed.value, isTrue);
    await tester.tap(find.text('确认放弃'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(live.active.value, isFalse);
    expect(find.text('开始录音'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'cleanup after a failed start does not create a phantom pending meeting',
    () async {
      stopThrows = true;
      await expectLater(live.end(), throwsException);
      expect(live.active.value, isFalse);
      expect(live.saveFailed.value, isFalse);
      expect(calls, ['stop']);
    },
  );
}
