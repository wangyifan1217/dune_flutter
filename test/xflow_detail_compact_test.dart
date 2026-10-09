import 'package:dunes_app/features/xflow/xflow_detail_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short approval fields sit on one row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: XfDetKv(label: '申请人', value: '叶锦成'),
        ),
      ),
    );

    expect(find.byType(Row), findsOneWidget);
    expect(find.byType(Column), findsNothing);
    final value = tester.widget<Text>(find.text('叶锦成'));
    expect(value.textAlign, TextAlign.right);
  });

  testWidgets('long approval text stays stacked', (tester) async {
    const body =
        '9 月出行金核销结算，按合同约定在次月 15 日前支付渠道服务费。发票已齐，金额与对账单一致。';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: XfDetKv(label: '事由', value: body),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byType(Row), findsNothing);
  });
}
