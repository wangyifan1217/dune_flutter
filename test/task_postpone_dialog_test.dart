import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/tasks/task_postpone_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('postpone dialog requires a later due date', (tester) async {
    const task = TaskItem(
      id: 1,
      title: '跟进方案',
      ownerUserId: 1,
      creatorUserId: 1,
      startAt: null,
    );
    final dated = TaskItem(
      id: task.id,
      title: task.title,
      ownerUserId: task.ownerUserId,
      creatorUserId: task.creatorUserId,
      startAt: DateTime(2026, 9, 1),
      dueAt: DateTime(2026, 9, 10, 23, 59, 59),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTaskPostponeDialog(context, task: dated),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('延期任务'), findsOneWidget);
    expect(find.text('新的截止日'), findsOneWidget);
    await tester.tap(find.text('确认延期'));
    await tester.pump();
    expect(find.text('请选择新的截止日'), findsOneWidget);
  });
}
