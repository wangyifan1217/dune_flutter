import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone-width sales and purchase list filters stay expanded as chips',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = AuthSession.fromJson(const {
        'userId': 11,
        'displayName': '王奕凡',
      });

      for (final kind in ['sales', 'purchase']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeProposalIntakePage(session: session, kind: kind),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(DropdownButton<String>), findsNothing);
        expect(find.widgetWithText(ChoiceChip, '全部'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, '草稿'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, '填写中'), findsOneWidget);
        expect(find.widgetWithText(ChoiceChip, '全部板块'), findsNothing);
        expect(find.text('库内提案'), findsOneWidget);
        expect(find.text('本日提案'), findsOneWidget);
        expect(find.text('本周提案'), findsOneWidget);
        expect(find.text('本月提案'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('proposal-period-day')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('proposal-period-day-selected')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('proposal-period-all')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('proposal-period-all-selected')),
          findsOneWidget,
        );
      }
    },
  );
}
