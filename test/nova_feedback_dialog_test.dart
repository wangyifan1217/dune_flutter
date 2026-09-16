import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_feedback_dialog.dart';

void main() {
  testWidgets('feedback dialog requires content and secondary confirm', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => NovaFeedbackDialog.show(context),
              child: const Text('打开反馈'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开反馈'));
    await tester.pumpAndSettle();

    expect(find.text('功能反馈'), findsOneWidget);
    expect(find.text('投诉'), findsOneWidget);

    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('确认提交？'), findsNothing);

    await tester.enterText(find.byType(TextField), '审批列表打开很慢');
    await tester.tap(find.text('投诉'));
    await tester.pump();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(find.text('确认提交？'), findsOneWidget);
    expect(find.textContaining('即将提交一条「投诉」'), findsOneWidget);

    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(find.text('确认提交？'), findsNothing);
    expect(find.text('反馈与投诉'), findsOneWidget);

    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(find.text('反馈与投诉'), findsNothing);
    expect(find.text('打开反馈'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
