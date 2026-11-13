import 'package:dunes_app/features/hr_performance/hr_performance_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('绩效选择面板支持搜索和选择', (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showHrReasonSheet(
                  context,
                  title: '处理申诉',
                  targets: ['review', 'hr', 'reject'],
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
    await tester.tap(find.text('主管初评'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索'), 'HR');
    await tester.pumpAndSettle();
    await tester.tap(find.text('HR 审核'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(result?['target'], 'hr');
  });
}
