import 'package:dunes_app/features/tasks/task_change_dialog.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses pending change request and field diffs', () {
    final req = TaskChangeRequest.fromJson({
      'id': 9,
      'taskId': 3,
      'kind': 'assignment',
      'status': 'pending',
      'requesterUserId': 1,
      'approverUserId': 2,
      'overdueAtSubmit': true,
      'requesterName': '张三',
      'approverName': '李主管',
      'changes': [
        {'field': 'owner', 'from': '张三', 'to': '王五'},
        {'field': 'dueAt', 'from': '2026-09-10', 'to': '2026-09-20'},
      ],
    });

    expect(req.isPending, isTrue);
    expect(req.isAssignment, isTrue);
    expect(req.overdueAtSubmit, isTrue);
    expect(taskPendingChangeLabel(req.kind), '指派待审批');
    expect(taskChangeFieldLabel('owner'), '负责人');
    expect(req.changes.first.to, '王五');
  });

  test('task item keeps original content when change is pending', () {
    final task = TaskItem.fromJson({
      'id': 3,
      'title': '原文标题',
      'ownerUserId': 1,
      'creatorUserId': 1,
      'hasPendingChange': true,
      'pendingChangeKind': 'change',
    });
    expect(task.title, '原文标题');
    expect(task.hasPendingChange, isTrue);
    expect(taskPendingChangeLabel(task.pendingChangeKind), '修改待审批');
  });

  testWidgets('change dialog submits only edited fields', (tester) async {
    const task = TaskItem(
      id: 1,
      title: '跟进方案',
      description: '原内容',
      ownerUserId: 1,
      creatorUserId: 1,
      dueAt: null,
    );
    TaskChangeDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              draft = await showTaskChangeDialog(context, task: task);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('修改任务'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '标题'), '新标题');
    await tester.tap(find.byKey(const Key('task-change-submit')));
    await tester.pumpAndSettle();
    expect(draft?.title, '新标题');
    expect(draft?.description, isNull);
  });
}
