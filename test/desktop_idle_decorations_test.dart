import 'package:dunes_app/features/conversation/comm_unread_notifier.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:dunes_app/features/nova/nova_widgets.dart';
import 'package:dunes_app/core/navigation/navigation_controller.dart';
import 'package:dunes_app/features/shell/dunes_main_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox NOVA eyes do not keep scheduling frames', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInboxHeader(
            onOpenContacts: () {},
            onOpenNova: () {},
            novaUnread: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('消息'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('unread side rail dot does not pulse', (tester) async {
    final nav = DunesNavigationController();
    final unread = CommUnreadNotifier()..update(3);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DunesMainTabBar(
            navigation: nav,
            activeScreen: 'C1',
            axis: Axis.vertical,
            commUnread: unread,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('通讯'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('NOVA empty state does not loop a blink ticker', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NovaC4EmptyState())),
    );
    await tester.pump();
    expect(find.text('今天想做些什么呢？'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
