import 'package:dunes_app/features/conversation/im_user_status.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:dunes_app/features/desktop/desktop_esc_minimize.dart';
import 'package:dunes_app/features/desktop/desktop_popover_dismissals.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('narrow desktop header keeps long status and actions separate', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var contacts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SizedBox(
              width: 260,
              child: ChatInboxHeader(
                onOpenContacts: () => contacts++,
                onNewChat: () {},
                onOpenNova: () {},
                novaThinking: true,
                selfImStatus: const ImUserStatusValue(
                  key: ImUserStatusCatalog.custom,
                  text: '正在处理重要工作暂时无法回复',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('小饕正在思考'), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通讯录'));
    expect(contacts, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'popover dismissal handles topmost once and removes disposed handlers',
    () {
      final calls = <int>[];
      void first() => calls.add(1);
      void second() => calls.add(2);
      DesktopPopoverDismissals.add(first);
      DesktopPopoverDismissals.add(second);
      expect(DesktopPopoverDismissals.dismissTopmost(), isTrue);
      expect(calls, [2]);
      DesktopPopoverDismissals.remove(first);
      expect(DesktopPopoverDismissals.dismissTopmost(), isFalse);
    },
  );

  testWidgets(
    'Escape closes inbox popover and returns focus without minimizing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DesktopEscMinimize(
            child: Scaffold(
              body: Column(
                children: [
                  ChatInboxHeader(
                    onOpenContacts: () {},
                    showNovaLeading: false,
                  ),
                  TextField(focusNode: focus),
                ],
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('通讯录'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('通讯录'), findsNothing);
      expect(
        Focus.of(
          tester.element(find.byIcon(Icons.more_horiz_rounded)),
        ).hasFocus,
        isTrue,
      );
      expect(DesktopPopoverDismissals.dismissTopmost(), isFalse);
      expect(tester.takeException(), isNull);
      // Keyboard reopening confirms focus returned to the triggering button.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(DesktopPopoverDismissals.dismissTopmost(), isFalse);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('desktop search scales height and keeps entry actionable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var calls = 0;
    for (final scale in [1.0, 1.3, 1.5]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: ChatInboxSearchBar(onTap: () => calls++),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chrome = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        chrome.constraints!.minHeight,
        closeTo(34 + 13 * (scale - 1), .01),
      );
      await tester.tap(find.text('搜索'));
      expect(tester.takeException(), isNull);
    }
    expect(calls, 3);
    debugDefaultTargetPlatformOverride = null;
  });
}
