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
      PointerScrollEvent(position: box.center, scrollDelta: const Offset(0, 160)),
    );
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
  });
}
