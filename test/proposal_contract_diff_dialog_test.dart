import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('长合同原文对照可以滚动，不出现底部溢出', (tester) async {
    final original = List.filled(80, '1.1 甲方与乙方就线上加油销售分成达成约定。').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => ProposalContractDiffDialog(
                    label: '销售合同核心条款',
                    original: original,
                    current: '已删减后的核心条款',
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('查看「销售合同核心条款」改动'), findsOneWidget);
    expect(find.text('合同匹配原文'), findsOneWidget);
    expect(find.text('确认后的内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
