import 'package:dunes_app/features/reconciliation/recon_pinned_table.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_models.dart';
import 'package:dunes_app/features/reconciliation/tag2_entity_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tag2 daily settlement renders as a pinned list like tag3', (
    tester,
  ) async {
    final snap = Tag2EntitySnapshot.fromJson({
      'asOfDate': '2026-09-28',
      'rows': [
        {
          'rowKey': '440000||中石油广东',
          'rowType': 'DETAIL',
          'provinceName': '广东',
          'counterpartyName': '中石油广东',
          'ourEntityName': '我方',
          'confirmationStatus': 'WAIT_BUSINESS',
          'canConfirmStage': 'BUSINESS',
          'businessBy': '甲',
          'operationBy': '乙',
          'amounts': [
            {
              'key': 'transit',
              'label': '在途资金',
              'display': '3.00',
              'drill': true,
            },
            {
              'key': 'prepayment',
              'label': '期末预付款余额',
              'display': '1.00',
              'drill': true,
            },
          ],
        },
        {
          'rowKey': 'ALL',
          'rowType': 'TOTAL',
          'amounts': [
            {
              'key': 'transit',
              'label': '在途资金',
              'display': '3.00',
              'drill': false,
            },
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 640,
            child: Tag2EntityTable(
              rows: snap.rows,
              comments: snap.comments,
              busyKeys: const {},
              onDrill: (row, amount) {},
              onConfirm: (row) {},
              onComment: (row) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReconPinnedTable), findsOneWidget);
    expect(find.text('省份'), findsOneWidget);
    expect(find.text('对方主体'), findsOneWidget);
    expect(find.text('审核记录'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    expect(find.text('在途资金'), findsOneWidget);
    expect(find.text('广东'), findsOneWidget);
    expect(find.text('中石油广东'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('意见'), findsOneWidget);
    expect(find.text('合计'), findsOneWidget);
    expect(find.text('提意见'), findsNothing);
  });
}
