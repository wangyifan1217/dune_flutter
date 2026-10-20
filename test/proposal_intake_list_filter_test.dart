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

        expect(
          find.byKey(const ValueKey('proposal-lighthouse-list')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('proposal-status-strip')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('proposal-period-strip')),
          findsOneWidget,
        );
        expect(find.byType(DropdownButton<String>), findsNothing);
        // 状态改成灯塔式文字页签（不再是 ChoiceChip）。
        final strip = find.byKey(const ValueKey('proposal-status-strip'));
        expect(find.descendant(of: strip, matching: find.text('全部')), findsOneWidget);
        expect(find.descendant(of: strip, matching: find.text('草稿')), findsOneWidget);
        expect(find.descendant(of: strip, matching: find.text('填写中')), findsOneWidget);
        expect(find.text('全部板块'), findsNothing);
        // 时间、分类收成两个下拉，默认「全部」；不再单独一行「提案明细 N 份」。
        expect(
          find.byKey(const ValueKey('proposal-period-all-selected')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('proposal-sector-filter')),
          findsOneWidget,
        );
        expect(find.text('提案明细'), findsNothing);
        // 打开时间下拉：「全部」一定在；数为 0 的时间段不列出来。
        await tester.tap(find.byKey(const ValueKey('proposal-period-strip')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('proposal-period-all')), findsOneWidget);
        expect(find.byKey(const ValueKey('proposal-period-day')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('proposal-period-all')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('proposal-period-all-selected')),
          findsOneWidget,
        );
      }
    },
  );
}
