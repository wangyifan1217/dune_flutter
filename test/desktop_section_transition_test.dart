import 'package:dunes_app/core/widgets/desktop_section_transition.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'rapid section transitions retain draft and focus and finish once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final token = ValueNotifier(0);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(token.dispose);
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: token,
              builder: (context, value, _) => DesktopSectionTransition(
                token: value,
                child: TextField(controller: controller, focusNode: focus),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '未发送草稿');
      final state = tester.state(find.byType(TextField));
      token.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      token.value = 2;
      await tester.pump();
      token.value = 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.text, '未发送草稿');
      expect(focus.hasFocus, isTrue);
      expect(tester.state(find.byType(TextField)), same(state));
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(DesktopSectionTransition),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('reduced motion and mobile bypass section movement', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.windows, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: DesktopSectionTransition(token: 2, child: const Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (platform == TargetPlatform.windows) {
        expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      } else {
        expect(find.byType(Transform), findsNothing);
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
