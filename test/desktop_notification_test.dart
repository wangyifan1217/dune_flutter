import 'package:dunes_app/features/push/desktop_notification_card.dart';
import 'package:dunes_app/features/push/in_app_message_banner.dart';
import 'package:dunes_app/features/shell/dunes_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    dismissInAppMessageBanner();
    dismissDunesActionToast();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testWidgets('$platform message close, navigation and replacement', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      late BuildContext context;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      void show(String title) => showInAppMessageBanner(
        context: context,
        conversationId: 42,
        title: title,
        body: '这是一条消息摘要',
        onTap: () => taps++,
      );
      show('测试会话');
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(DesktopNotificationCard));
      expect(rect.width, 360);
      expect(rect.top, greaterThanOrEqualTo(64));
      await tester.tap(find.byTooltip('关闭通知'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(inAppMessageBannerConversationId, 0);
      show('旧消息');
      await tester.pumpAndSettle();
      show('新消息');
      await tester.pumpAndSettle();
      expect(find.text('旧消息'), findsNothing);
      await tester.tap(find.text('查看消息'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byType(DesktopNotificationCard), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('$platform dark narrow window and actionable notification', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.reset();
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext context;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      showDunesActionToast(
        context,
        List.filled(100, '很长的通知正文😀').join(),
        onTap: () => taps++,
        actionLabel: '立即处理',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DesktopNotificationCard)).width,
        lessThanOrEqualTo(284),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('立即处理'));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byType(DesktopNotificationCard), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('hover pauses message dismissal', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    showInAppMessageBanner(
      context: context,
      conversationId: 1,
      title: '提醒',
      body: '内容',
      onTap: () {},
      duration: const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DesktopNotificationCard)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(DesktopNotificationCard), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNotificationCard), findsNothing);
    await mouse.removePointer();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile retains its original banner', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    showInAppMessageBanner(
      context: context,
      conversationId: 1,
      title: '手机通知',
      body: '内容',
      onTap: () {},
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopNotificationCard), findsNothing);
    expect(find.byType(Dismissible), findsOneWidget);
    dismissInAppMessageBanner();
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
