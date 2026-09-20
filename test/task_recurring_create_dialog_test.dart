import 'package:dunes_app/features/tasks/task_recurring_create_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode monthly day weekly and daily tokens', () {
    expect(
      encodeTaskRecurringFrequency(kind: 'monthly', monthDay: '每月10日'),
      '每月10日',
    );
    expect(
      encodeTaskRecurringFrequency(kind: 'monthly', monthDay: '每月最后工作日'),
      '每月最后工作日',
    );
    expect(
      encodeTaskRecurringFrequency(kind: 'weekly', weekday: '每周五'),
      '每周五',
    );
    expect(encodeTaskRecurringFrequency(kind: 'daily'), '每天');
    expect(kTaskRecurringMonthDays.last.$2, '最后工作日');
    expect(kTaskRecurringMonthDays[9].$1, '每月10日');
  });

  test('frequency label maps stored tokens to display text', () {
    expect(taskRecurringFrequencyLabel('每月'), '每月 1 日');
    expect(taskRecurringFrequencyLabel('每月10日'), '每月 10 日');
    expect(taskRecurringFrequencyLabel('每月最后工作日'), '每月最后工作日');
    expect(taskRecurringFrequencyLabel('每周五'), '每周五');
    expect(taskRecurringFrequencyLabel(''), '未设置周期');
    expect(taskRecurringFrequencyLabel('自定义'), '自定义');
  });

  testWidgets('create dialog splits cycle kind and monthly day', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTaskRecurringCreateDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('新建周期任务'), findsOneWidget);
    expect(find.text('重复周期'), findsOneWidget);
    expect(find.text('每月哪一天'), findsOneWidget);
    expect(find.text('10 日'), findsOneWidget);
    expect(find.textContaining('每月 10 日'), findsWidgets);
    expect(find.text('开始日期 YYYY-MM-DD'), findsNothing);

    await tester.tap(find.byKey(const Key('recurring-create-submit')));
    await tester.pump();
    expect(find.text('请填写任务名称'), findsOneWidget);

    await tester.tap(find.byKey(const Key('recurring-month-day')));
    await tester.pumpAndSettle();
    expect(find.text('11 日').hitTestable(), findsWidgets);
    expect(find.text('9 日').hitTestable(), findsWidgets);
  });
}
