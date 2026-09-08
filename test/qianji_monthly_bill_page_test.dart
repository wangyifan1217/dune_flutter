import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/qianji/native_qianji_monthly_bill_page.dart';
import 'package:dunes_app/features/qianji/qianji_monthly_bill_demo.dart';

void main() {
  test('default month is previous calendar month', () {
    expect(
      monthlyBillDefaultMonth(now: DateTime(2026, 9, 8)),
      '2026-08',
    );
    final months = monthlyBillMonthOptions(now: DateTime(2026, 9, 8));
    expect(months, contains('2026-08'));
    expect(months.length, 12);
  });

  test('august demo splits receivable and payable', () {
    final board = monthlyBillDemoBoard('2026-08');
    expect(board.receivable.count, 4);
    expect(board.payable.count, 3);
    expect(board.receivable.overdueCount, greaterThan(0));
    expect(board.payable.supplyYuan, greaterThan(board.payable.channelYuan));
  });

  testWidgets('monthly bill page shows receivable then payable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiMonthlyBillPage(onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('月结'), findsOneWidget);
    expect(find.text('应收总览'), findsOneWidget);
    expect(find.text('电子券销售款'), findsOneWidget);

    await tester.tap(find.text('应付'));
    await tester.pumpAndSettle();
    expect(find.text('应付总览'), findsOneWidget);
    expect(find.text('电子券采购款'), findsWidgets);

    await tester.tap(find.byKey(const Key('monthly-bill-overdue')));
    await tester.pumpAndSettle();
    expect(find.textContaining('逾期'), findsWidgets);

    final bill = find.text('电子券采购款').first;
    await tester.ensureVisible(bill);
    await tester.pumpAndSettle();
    await tester.tap(bill);
    await tester.pumpAndSettle();
    expect(find.text('账单周期'), findsOneWidget);
    expect(find.text('对方主体'), findsOneWidget);
  });
}
