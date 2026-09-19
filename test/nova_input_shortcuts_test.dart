import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_widgets.dart';

void main() {
  testWidgets('input bar shows Alipay-style shortcuts under the field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var moreOpened = false;
    var meetingOpened = false;
    var kbOpened = false;
    var cameraOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaC4InputBar(
            controller: TextEditingController(),
            focusNode: FocusNode(),
            voiceMode: false,
            sending: false,
            enabled: true,
            hintText: '问小饕...',
            modelLabel: 'GPT',
            quickActionsOpen: moreOpened,
            onToggleVoice: () {},
            onSend: () {},
            onPickModel: () {},
            onInputFocused: () {},
            onToggleQuickActions: () => moreOpened = true,
            onOpenKb: () => kbOpened = true,
            onOpenMeeting: () => meetingOpened = true,
            onVoiceCall: () {},
            onCamera: () => cameraOpened = true,
            onAlbum: () {},
            onHistory: () {},
            onNewChat: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('知识库'), findsOneWidget);
    expect(find.text('会议'), findsOneWidget);
    expect(find.text('电话'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.byIcon(Icons.groups_2_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);

    await tester.tap(find.text('会议'));
    await tester.pump();
    expect(meetingOpened, isTrue);

    await tester.tap(find.text('知识库'));
    await tester.pump();
    expect(kbOpened, isTrue);

    await tester.tap(find.text('更多'));
    await tester.pump();
    expect(moreOpened, isTrue);
    expect(cameraOpened, isFalse);
  });

  testWidgets('APP swipe up on shortcut strip opens more tools', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var moreOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaC4InputBar(
            controller: TextEditingController(),
            focusNode: FocusNode(),
            voiceMode: false,
            sending: false,
            enabled: true,
            hintText: '问小饕...',
            modelLabel: 'GPT',
            quickActionsOpen: false,
            onToggleVoice: () {},
            onSend: () {},
            onPickModel: () {},
            onInputFocused: () {},
            onToggleQuickActions: () => moreOpened = true,
            onOpenKb: () {},
            onOpenMeeting: () {},
            onVoiceCall: () {},
            onCamera: () {},
            onAlbum: () {},
            onHistory: () {},
            onNewChat: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.fling(find.text('更多'), const Offset(0, -80), 800);
    await tester.pumpAndSettle();
    expect(moreOpened, isTrue);
  });

  testWidgets('expanded more grid shows extra tools', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovaC4InputBar(
            controller: TextEditingController(),
            focusNode: FocusNode(),
            voiceMode: false,
            sending: false,
            enabled: true,
            hintText: '问小饕...',
            modelLabel: 'GPT',
            quickActionsOpen: true,
            onToggleVoice: () {},
            onSend: () {},
            onPickModel: () {},
            onInputFocused: () {},
            onToggleQuickActions: () {},
            onOpenKb: () {},
            onOpenMeeting: () {},
            onVoiceCall: () {},
            onCamera: () {},
            onAlbum: () {},
            onAttach: () {},
            onMeetingPrd: () {},
            onHistory: () {},
            onNewChat: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('收起'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('PRD'), findsOneWidget);
    expect(find.text('新对话'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('GPT'), findsOneWidget);
  });
}
