import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/nova/nova_background_coordinator.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'desktop avatar updates on completion and clears only when unread replies are read',
    (tester) async {
      final coordinator = NovaBackgroundCoordinator.instance;
      coordinator.setNovaPageActive(false);
      final nav = DunesNavigationController();
      addTearDown(nav.dispose);
      addTearDown(() {
        coordinator.markReplySeen(9001);
        coordinator.markReplySeen(9002);
        coordinator.setNovaPageActive(false);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                DunesMainTabBar(
                  navigation: nav,
                  activeScreen: 'C1',
                  axis: Axis.vertical,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dot = find.byKey(const ValueKey('nova-rail-unread-dot'));
      expect(dot, findsNothing);
      coordinator.markPendingCommBadgeBump(conversationId: 9001);
      await tester.pump();
      expect(dot, findsOneWidget);
      coordinator.markPendingCommBadgeBump(conversationId: 9002);
      coordinator.markReplySeen(9001);
      await tester.pump();
      expect(dot, findsOneWidget);
      coordinator.markReplySeen(9002);
      await tester.pump();
      expect(dot, findsNothing);
      coordinator.setNovaPageActive(true, conversationId: 9001);
      coordinator.markPendingCommBadgeBump(conversationId: 9001);
      await tester.pump();
      expect(dot, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
