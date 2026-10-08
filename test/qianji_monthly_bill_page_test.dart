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

  test('search and project buckets keep unpaid bills together', () {
    final rows = monthlyBillDemoBoard('2026-08')
        .rows
        .where((row) => row.side == 'receivable');
    final hit = rows.where((row) => monthlyBillMatchesQuery(row, '平安')).toList();
    expect(hit, hasLength(1));
    expect(monthlyBillMatchesQuery(hit.single, '不存在的词'), isFalse);

    final buckets = monthlyBillBuckets(
      rows.where((row) => row.side == 'receivable'),
      byEntity: false,
    );
    expect(buckets.first.name, '平安(共享平台)');
    expect(buckets.map((b) => b.name), contains('未填项目'));
    final blank = buckets.firstWhere((b) => b.name == '未填项目');
    expect(blank.count, 2);
  });

  test('august demo splits receivable and payable', () {
    final board = monthlyBillDemoBoard('2026-08');
    expect(board.receivable.count, 4);
    expect(board.payable.count, 3);
    expect(board.receivable.overdueCount, greaterThan(0));
    expect(board.payable.supplyYuan, greaterThan(board.payable.channelYuan));
  });

  testWidgets('monthly bill page shows receivable then payable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiMonthlyBillPage(onBack: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('月结'), findsOneWidget);
    expect(find.text('应收总览'), findsOneWidget);
    expect(find.text('电子券销售款'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('monthly-bill-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('monthly-bill-search')), '支付宝');
    await tester.pumpAndSettle();
    expect(find.text('平台服务费'), findsOneWidget);
    expect(find.text('电子券销售款'), findsNothing);

    await tester.enterText(find.byKey(const Key('monthly-bill-search')), '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('monthly-bill-lens-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('monthly-bill-lens-project')));
    await tester.pumpAndSettle();
    expect(find.text('平安(共享平台)'), findsOneWidget);
    expect(find.text('未填项目'), findsOneWidget);

    await tester.ensureVisible(find.text('平安(共享平台)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('平安(共享平台)'));
    await tester.pumpAndSettle();
    expect(find.text('电子券销售款'), findsOneWidget);
    expect(find.text('平台服务费'), findsNothing);

    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('monthly-bill-lens-entity')));
    await tester.pumpAndSettle();
    expect(find.text('上海卓悦优泰新能源科技有限公司'), findsOneWidget);

    await tester.tap(find.byKey(const Key('monthly-bill-lens-bills')));
    await tester.pumpAndSettle();
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
