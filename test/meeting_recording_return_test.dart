import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/native_audio_recorder.dart';
import 'package:dunes_app/features/meeting/meeting_live_controller.dart';
import 'package:dunes_app/features/meeting/meeting_recording_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  var nativeRecording = false;
  var nativePaused = false;
  var stalled = false;
  var silenced = false;
  var bytes = 0;
  var resumeCalls = 0;
  var resumeFailures = 0;
  var startCalls = 0;
  var nativeReason = '';
  var notificationTap = false;
  Completer<bool>? resumeGate;

  Future<void> elapse(WidgetTester tester, [int ticks = 130]) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> sendEvent(
    WidgetTester tester,
    String kind, [
    String reason = '',
  ]) async {
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'dunes/audio_recorder_events',
      const StandardMethodCodec().encodeSuccessEnvelope({
        'kind': kind,
        'reason': reason,
      }),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> interrupt(
    WidgetTester tester, [
    String reason = 'audioRecordSilent',
  ]) async {
    nativePaused = true;
    nativeReason = reason;
    await sendEvent(tester, 'paused', reason);
  }

  Future<void> background(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await elapse(tester);
  }

  void meetingTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        if (resumeGate != null && !resumeGate!.isCompleted) {
          resumeGate!.complete(true);
        }
        await elapse(tester, 15);
        if (live.isActive) await live.end();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUp(() {
    nativeRecording = false;
    nativePaused = false;
    stalled = false;
    silenced = false;
    bytes = 0;
    resumeCalls = 0;
    resumeFailures = 0;
    startCalls = 0;
    nativeReason = '';
    notificationTap = false;
    resumeGate = null;
    live.consumeRecordedFile();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, (call) async {
          switch (call.method) {
            case 'start':
              startCalls++;
              nativeRecording = true;
              nativePaused = false;
              return true;
            case 'pause':
              nativePaused = true;
              return true;
            case 'resume':
              resumeCalls++;
              if (resumeCalls <= resumeFailures) {
                throw PlatformException(code: 'BUSY');
              }
              if (resumeGate != null) await resumeGate!.future;
              nativePaused = false;
              return true;
            case 'status':
              if (nativeRecording && !nativePaused && !stalled) bytes += 6400;
              return {
                'isRecording': nativeRecording,
                'isPaused': nativePaused,
                'capturedBytes': bytes,
                'durationMs': bytes * 1000 ~/ 32000,
                'pauseReason': nativeReason,
                'captureSilenced': silenced,
              };
            case 'consumeMeetingNotificationTap':
              final value = notificationTap;
              notificationTap = false;
              return value;
            case 'stop':
              nativeRecording = false;
              return {'path': '/recording/meeting.wav', 'durationMs': 1000};
            default:
              return true;
          }
        });
  });

  setUpAll(() async {
    for (final (family, asset) in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ('Geist', 'assets/fonts/Geist-Regular.ttf'),
      ('Noto Sans SC', 'assets/fonts/NotoSansSC-Regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
    }
  });

  tearDown(() async {
    if (live.active.value) await live.end();
    live.consumeRecordedFile();
    NativeAudioRecorder.isStartBlocked = null;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });

  meetingTest(
    'foreground retries twice after failures and resumes the same recording on attempt three',
    (tester) async {
      await live.start(session, title: '产品周会');
      await interrupt(tester);
      resumeFailures = 2;
      final sync = live.syncOnForeground();
      await elapse(tester);
      await sync;
      expect(resumeCalls, 3);
      expect(startCalls, 1);
      expect(live.paused.value, isFalse);
      expect(live.recovering.value, isFalse);
      expect(live.interruptionHint.value, '已自动继续录音');
    },
  );

  meetingTest(
    'exhausted retries remain paused and never claim microphone availability',
    (tester) async {
      await live.start(session, title: '产品周会');
      await interrupt(tester);
      resumeFailures = 99;
      final sync = live.syncOnForeground();
      await elapse(tester);
      await sync;
      expect(resumeCalls, 3);
      expect(live.paused.value, isTrue);
      expect(live.recovering.value, isFalse);
      expect(live.interruptionHint.value, contains('失败'));
      expect(live.interruptionHint.value, isNot(contains('已可用')));
    },
  );

  for (final systemSilenced in [false, true]) {
    meetingTest(
      'native resume without ${systemSilenced ? 'microphone access' : 'new audio bytes'} is not successful',
      (tester) async {
        await live.start(session, title: '产品周会');
        await interrupt(tester);
        stalled = !systemSilenced;
        silenced = systemSilenced;
        final sync = live.syncOnForeground();
        await elapse(tester, 150);
        await sync;
        expect(resumeCalls, 3);
        expect(live.paused.value, isTrue);
        expect(live.interruptionHint.value, isNot('已自动继续录音'));
      },
    );
  }

  meetingTest('manual pause wins even over a late native resumed event', (
    tester,
  ) async {
    await live.start(session, title: '产品周会');
    await live.pause();
    await live.syncOnForeground();
    nativePaused = false;
    await sendEvent(tester, 'resumed');
    await elapse(tester, 5);
    expect(resumeCalls, 0);
    expect(live.userPaused, isTrue);
    expect(live.paused.value, isTrue);
    expect(nativePaused, isTrue);
  });

  meetingTest('ending while resume is in flight cannot revive the session', (
    tester,
  ) async {
    await live.start(session, title: '产品周会');
    await interrupt(tester);
    resumeGate = Completer<bool>();
    final sync = live.syncOnForeground();
    await elapse(tester, 8);
    expect(resumeCalls, 1);
    final end = live.end();
    resumeGate!.complete(true);
    await elapse(tester, 5);
    await sync;
    await end;
    expect(live.isActive, isFalse);
    expect(nativeRecording, isFalse);
    expect(live.interruptionHint.value, isNull);
  });

  meetingTest('manual pause cancels a resume that is already in flight', (
    tester,
  ) async {
    await live.start(session, title: '产品周会');
    await interrupt(tester);
    resumeGate = Completer<bool>();
    final sync = live.syncOnForeground();
    await elapse(tester, 8);
    final pause = live.pause();
    resumeGate!.complete(true);
    await elapse(tester, 5);
    await pause;
    await sync;
    expect(nativePaused, isTrue);
    expect(live.userPaused, isTrue);
    expect(live.paused.value, isTrue);
  });

  meetingTest(
    'missing native session offers recovery instead of trying to resume a dead recorder',
    (tester) async {
      await live.start(session, title: '产品周会');
      nativeRecording = false;
      await live.syncOnForeground();
      expect(live.saveFailed.value, isTrue);
      expect(live.paused.value, isTrue);
      expect(resumeCalls, 0);
    },
  );

  for (final reason in ['routeDeviceLost', 'audioFileWriteError']) {
    meetingTest('$reason does not auto resume when its event was missed', (
      tester,
    ) async {
      await live.start(session, title: '产品周会');
      nativePaused = true;
      nativeReason = reason;
      await live.syncOnForeground();
      expect(live.paused.value, isTrue);
      expect(resumeCalls, 0);
    });
  }

  Future<DunesNavigationController> mount(
    WidgetTester tester, {
    bool dark = false,
    double scale = 1,
    double navExtent = 0,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final navigation = DunesNavigationController(initialScreen: 'C1');
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('meeting-preview-capture'),
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: 'Geist',
            fontFamilyFallback: const ['Noto Sans SC'],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: MeetingRecordingCoordinator(
              navigation: navigation,
              child: ListenableBuilder(
                listenable: navigation,
                builder: (context, _) => MeetingRecordingLayout(
                  visible: navigation.currentScreen != 'MM0',
                  bottomNavigationExtent: navExtent,
                  onOpen: () => openCurrentMeeting(navigation),
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(
                        navigation.currentScreen == 'MM0' ? '当前会议录音' : '工作台',
                      ),
                    ),
                    body: const Center(child: Text('产品周会')),
                    bottomNavigationBar: const SizedBox(
                      key: Key('composer'),
                      height: 52,
                      child: TextField(
                        decoration: InputDecoration(hintText: '输入消息'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return navigation;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (Platform.environment['DUNES_CAPTURE_PREVIEWS'] != '1') return;
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
        find.byKey(const Key('meeting-preview-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        'D:/workspace/new_dune_web/tmp/meeting-recording-previews/$name.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  meetingTest(
    'bar reserves composer space, opens the same meeting and disappears there',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await live.start(session, title: '产品周会');
      final nav = await mount(tester);
      expect(find.byKey(const Key('meeting-recording-bar')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('composer'))).bottom,
        lessThan(
          tester.getRect(find.byKey(const Key('meeting-recording-bar'))).top,
        ),
      );
      await capture(tester, 'recording-bar');
      await tester.tap(find.byKey(const Key('meeting-recording-bar')));
      await tester.pump();
      expect(nav.currentScreen, 'MM0');
      expect(find.byKey(const Key('meeting-recording-bar')), findsNothing);
      expect(startCalls, 1);
      nav.go('C5');
      await tester.pump();
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      await live.end();
      await tester.pump();
      expect(find.byKey(const Key('meeting-recording-bar')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  meetingTest(
    'return reminder appears once, closes without stopping and opens the current meeting',
    (tester) async {
      await live.start(session, title: '产品周会');
      final nav = await mount(tester);
      await background(tester);
      await foreground(tester);
      expect(find.text('会议录音仍在进行'), findsOneWidget);
      await capture(tester, 'return-recording');
      await tester.tap(find.text('留在当前页'));
      await elapse(tester, 5);
      expect(live.paused.value, isFalse);
      await foreground(tester);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      await background(tester);
      await interrupt(tester);
      await foreground(tester);
      expect(find.text('会议录音已自动继续'), findsOneWidget);
      await tester.tap(find.text('查看会议'));
      await elapse(tester, 5);
      expect(nav.currentScreen, 'MM0');
      expect(startCalls, 1);
      await background(tester);
      await foreground(tester);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  meetingTest(
    'failed resume dialog is truthful on narrow dark screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await live.start(session, title: '产品周会');
      await mount(tester, dark: true, scale: 1.3);
      await background(tester);
      await interrupt(tester);
      resumeFailures = 99;
      await foreground(tester);
      expect(find.byKey(const Key('meeting-return-dialog')), findsOneWidget);
      expect(find.text('进入会议处理'), findsOneWidget);
      expect(find.text('会议录音已自动继续'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, 'return-paused-dark');
      await tester.tap(find.text('留在当前页'));
      await elapse(tester, 5);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  meetingTest(
    'notification click opens meeting without a redundant return dialog',
    (tester) async {
      await live.start(session, title: '产品周会');
      final nav = await mount(tester);
      await background(tester);
      notificationTap = true;
      await foreground(tester);
      expect(nav.currentScreen, 'MM0');
      expect(notificationTap, isFalse);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  meetingTest(
    'bar clears the bottom navigation and the keyboard without covering the composer',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await live.start(session, title: '产品周会');
      await mount(tester, navExtent: 110);
      final bar = find.byKey(const Key('meeting-recording-bar'));
      expect(tester.getRect(bar).bottom, lessThanOrEqualTo(780 - 110));
      expect(
        tester.getRect(find.byKey(const Key('composer'))).bottom,
        lessThan(tester.getRect(bar).top),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.getRect(bar).bottom, lessThan(500));
      expect(
        tester.getRect(find.byKey(const Key('composer'))).bottom,
        lessThan(tester.getRect(bar).top),
      );
      expect(tester.takeException(), isNull);
    },
  );

  meetingTest(
    'permission-style inactive transitions do not show a return reminder',
    (tester) async {
      await live.start(session, title: '产品周会');
      await mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await foreground(tester);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
    },
  );

  meetingTest(
    'existing modal is respected and ending a meeting removes only its own reminder',
    (tester) async {
      await live.start(session, title: '产品周会');
      await mount(tester);
      final context = tester.element(find.byType(MeetingRecordingCoordinator));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('业务确认'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('完成确认'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await background(tester);
      await foreground(tester);
      expect(find.text('业务确认'), findsOneWidget);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      await tester.tap(find.text('完成确认'));
      await elapse(tester, 12);
      expect(find.byKey(const Key('meeting-return-dialog')), findsOneWidget);
      await live.end();
      await elapse(tester, 5);
      expect(find.byKey(const Key('meeting-return-dialog')), findsNothing);
      expect(find.text('工作台'), findsOneWidget);
    },
  );
}
