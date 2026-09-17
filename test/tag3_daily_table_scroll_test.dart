import 'package:dunes_app/core/widgets/horizontal_drag_scroll_view.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_preview.dart';
import 'package:dunes_app/features/reconciliation/tag3_daily_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tag3 daily table pans horizontally in a narrow pane', (
    tester,
  ) async {
    final snap = tag3DailyPreviewSnapshot(asOfDate: '2026-09-17');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: Tag3DailyTable(rows: snap.rows),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HorizontalDragScrollView), findsOneWidget);
    expect(find.text('审核记录'), findsOneWidget);

    final scrollable = find.descendant(
      of: find.byType(HorizontalDragScrollView),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.maxScrollExtent, greaterThan(0));

    await tester.drag(scrollable, const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
  });
}
