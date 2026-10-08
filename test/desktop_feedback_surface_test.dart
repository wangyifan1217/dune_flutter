import 'package:dunes_app/core/widgets/desktop_feedback_surface.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop search and Nova segments support keyboard activation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var searches = 0;
    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    ChatInboxSearchBar(onTap: () => searches++),
                    NovaPageHeader(tabController: tabs, onBack: () {}),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    final searchInk = find.descendant(
      of: find.byType(ChatInboxSearchBar),
      matching: find.byType(InkWell),
    );
    Focus.of(
      tester.element(
        find.descendant(of: searchInk, matching: find.byType(Text)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(searches, 1);
    Focus.of(
      tester.element(find.text(NovaPageHeader.tabLabels[1])),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tabs.index, 1);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'desktop hover and keyboard feedback retain hit area and callback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DesktopFeedbackSurface(
                onTap: () => taps++,
                visualInset: const EdgeInsets.all(6),
                child: const SizedBox(
                  width: 200,
                  height: 60,
                  child: Text('会话'),
                ),
              ),
            ),
          ),
        ),
      );
      final target = find.byType(DesktopFeedbackSurface);
      final before = tester.getRect(target);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      final box = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      expect(tester.getRect(target), before);
      await tester.tapAt(before.topLeft + const Offset(2, 2));
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 2);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'mobile keeps original InkWell and reduced motion disables transition',
    (tester) async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.windows]) {
        debugDefaultTargetPlatformOverride = platform;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: DesktopFeedbackSurface(
                  onTap: () {},
                  child: const SizedBox(width: 200, height: 60),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(AnimatedContainer), findsNothing);
        } else {
          expect(
            tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .duration,
            Duration.zero,
          );
        }
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
