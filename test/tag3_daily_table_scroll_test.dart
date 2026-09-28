import 'package:dunes_app/features/reconciliation/tag3_daily_models.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_preview.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_table.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _scrollable(AxisDirection direction) {
  return find.byWidgetPredicate(
    (widget) => widget is Scrollable && widget.axisDirection == direction,
  );
}

Future<void> _pumpTable(WidgetTester tester, {double height = 220}) async {
  final snap = tag3DailyPreviewSnapshot(asOfDate: '2026-09-17');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: height,
          child: Tag3DailyTable(rows: snap.rows),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tag3 daily table pans horizontally in a narrow pane', (
    tester,
  ) async {
    await _pumpTable(tester, height: 640);
    expect(find.text('审核记录'), findsOneWidget);

    final horizontal = _scrollable(AxisDirection.right);
    expect(horizontal, findsWidgets);
    final state = tester.state<ScrollableState>(horizontal.first);
    expect(state.position.maxScrollExtent, greaterThan(0));

    final origin = tester.getRect(find.byType(Tag3DailyTable)).center;
    await tester.dragFrom(origin, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
  });

  testWidgets('tag3 daily table scrolls vertically when rows overflow', (
    tester,
  ) async {
    await _pumpTable(tester);

    final vertical = _scrollable(AxisDirection.down);
    expect(vertical, findsWidgets);
    final state = tester.state<ScrollableState>(vertical.first);
    expect(state.position.maxScrollExtent, greaterThan(0));

    final origin = tester.getRect(find.byType(Tag3DailyTable)).center;
    await tester.dragFrom(origin, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
  });

  testWidgets('mouse wheel scrolls the daily table vertically', (tester) async {
    await _pumpTable(tester);
    final vertical = _scrollable(AxisDirection.down);
    final state = tester.state<ScrollableState>(vertical.first);
    final box = tester.getRect(find.byType(Tag3DailyTable));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: box.center,
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
  });

  testWidgets('header stays pinned while rows scroll vertically', (
    tester,
  ) async {
    await _pumpTable(tester);
    final headerY = tester.getTopLeft(find.text('渠道')).dy;
    final origin = tester.getRect(find.byType(Tag3DailyTable)).center;
    await tester.dragFrom(origin, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('渠道')).dy, headerY);
    expect(find.text('操作'), findsOneWidget);
  });

  testWidgets('action buttons stay pinned while panning horizontally', (
    tester,
  ) async {
    await _pumpTable(tester, height: 640);
    final actionX = tester.getTopLeft(find.text('操作')).dx;
    final opinion = find.text('意见').first;
    final opinionX = tester.getTopLeft(opinion).dx;
    final origin = tester.getRect(find.byType(Tag3DailyTable)).center;
    await tester.dragFrom(origin, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('操作')).dx, actionX);
    expect(tester.getTopLeft(find.text('意见').first).dx, closeTo(opinionX, 1));
  });

  testWidgets('action buttons are visible without opening a menu', (
    tester,
  ) async {
    await _pumpTable(tester, height: 640);
    expect(find.text('意见'), findsWidgets);
    expect(find.text('确认'), findsWidgets);
  });

  testWidgets('project rows share a tint and audit status uses role icons', (
    tester,
  ) async {
    const row = Tag3DailyRow(
      rowKey: '其他|测试',
      channelCategoryL1Name: '其他',
      projectName: '测试',
      period: 'DAY',
      periodLabel: '2026-09-26',
      statDate: '2026-09-26',
      paymentTerm: 'D+1',
      salesAmount: 0,
      writeOffAmount: 0,
      profitAmount: 0,
      cashFlowAmount: 0,
      cashReceivableAmount: 0,
      cashPaidAmount: 0,
      cashReceivableDiff: 0,
      subsidyReceivableAmount: 0,
      confirmationStatus: 'WAIT_BUSINESS',
      confirmationStatusLabel: '待业务确认',
      canConfirm: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 240,
            child: Tag3DailyTable(
              rows: const [
                row,
                Tag3DailyRow(
                  rowKey: '多渠道|一起加油',
                  channelCategoryL1Name: '多渠道',
                  projectName: '一起加油',
                  period: 'DAY',
                  periodLabel: '2026-09-27',
                  statDate: '2026-09-27',
                  paymentTerm: '预收',
                  salesAmount: 0,
                  writeOffAmount: 0,
                  profitAmount: 0,
                  cashFlowAmount: 0,
                  cashReceivableAmount: 0,
                  cashPaidAmount: 0,
                  cashReceivableDiff: 0,
                  subsidyReceivableAmount: 0,
                  confirmationStatus: 'WAIT_BUSINESS',
                  confirmationStatusLabel: '待业务确认',
                  canConfirm: false,
                ),
              ],
              assignees: const [
                Tag3DailyAssignee(
                  rowKey: '其他|测试',
                  businessUsers: [
                    Tag3DailyPerson(userId: '1', name: '李同池', phone: ''),
                  ],
                  operationUsers: [
                    Tag3DailyPerson(userId: '2', name: '吕奇', phone: ''),
                  ],
                ),
              ],
              comments: const [
                Tag3DailyComment(
                  id: 1,
                  rowKey: '其他|测试',
                  period: 'DAY',
                  statDate: '2026-09-26',
                  periodLabel: '2026-09-26',
                  projectName: '测试',
                  userId: 2,
                  userName: '吕奇',
                  kind: 'CONFIRM',
                  stage: 'OPERATION',
                  body: '',
                  createdAt: '2026-09-26T10:00:00',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('待业务确认'), findsNothing);
    expect(find.text('业务 李同池'), findsOneWidget);
    expect(find.text('运营 吕奇'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsWidgets);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    final fills = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color)
        .whereType<Color>()
        .toSet();
    expect(fills, contains(const Color(0xFFF3F0F8)));
    expect(fills, contains(const Color(0xFFFFFCF8)));
  });
}
