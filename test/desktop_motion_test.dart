import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/core/widgets/desktop_entrance.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'desktop navigation indicator moves without moving tab hit areas',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final active = ValueNotifier('C1');
      final navigation = DunesNavigationController();
      addTearDown(active.dispose);
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: active,
                  builder: (context, value, _) => DunesMainTabBar(
                    navigation: navigation,
                    activeScreen: value,
                    axis: Axis.vertical,
                    onSwitchMainTab: (value) => active.value = value,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.text('通讯'));
      expect(
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).top,
        17,
      );
      await tester.tap(find.text('灯塔'));
      await tester.pump();
      expect(active.value, 'LH');
      expect(
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).top,
        145,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('通讯')), rect);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'entrance settles and preserves child; reduced motion bypasses animation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var taps = 0;
      final child = TextButton(
        onPressed: () => taps++,
        child: const Text('操作'),
      );
      for (final reduce in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Scaffold(body: DesktopEntrance(child: child)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (reduce) {
          expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
        }
        await tester.tap(find.text('操作'));
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(taps, 2);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
