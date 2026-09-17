import 'package:dunes_app/features/conversation/im_user_status.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inbox header shows self status under 消息', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInboxHeader(
            onOpenContacts: () {},
            selfImStatus: const ImUserStatusValue(key: ImUserStatusCatalog.busy),
          ),
        ),
      ),
    );

    expect(find.text('消息'), findsOneWidget);
    expect(find.text('忙碌'), findsOneWidget);
    final titleY = tester.getTopLeft(find.text('消息')).dy;
    final statusY = tester.getTopLeft(find.text('忙碌')).dy;
    expect(statusY, greaterThan(titleY));
  });

  testWidgets('inbox header hides status under 消息 when unset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInboxHeader(onOpenContacts: () {}),
        ),
      ),
    );

    expect(find.text('消息'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });
}
