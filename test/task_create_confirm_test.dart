import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/tasks/native_task_form.dart';
import 'package:dunes_app/features/tasks/native_task_quick_create.dart';
import 'package:dunes_app/features/tasks/task_create_confirm.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: 't',
  apiBase: 'http://127.0.0.1',
  roles: [],
  displayName: '测试用户',
);

void main() {
  test('create range requires both dates and due after start', () {
    expect(taskCreateRangeError(null, null), '请选择开始时间和结束时间');
    expect(taskCreateRangeError(DateTime(2026, 9, 10), null), '请选择开始时间和结束时间');
    expect(taskCreateRangeError(null, DateTime(2026, 9, 12)), '请选择开始时间和结束时间');
    expect(
      taskCreateRangeError(DateTime(2026, 9, 12), DateTime(2026, 9, 10)),
      '结束时间不能早于开始时间',
    );
    expect(
      taskCreateRangeError(DateTime(2026, 9, 10), DateTime(2026, 9, 12)),
      isNull,
    );
  });

  test('create range label covers start, due, or both', () {
    expect(taskCreateRangeLabel(null, null), isNull);
    expect(
      taskCreateRangeLabel(DateTime(2026, 9, 10), DateTime(2026, 9, 12)),
      '2026-09-10 ~ 2026-09-12',
    );
    expect(taskCreateRangeLabel(DateTime(2026, 9, 10), null), '起 2026-09-10');
    expect(taskCreateRangeLabel(null, DateTime(2026, 9, 12)), '止 2026-09-12');
  });

  testWidgets('confirm dialog shows title and selected dates', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              confirmed = await confirmCreateTask(
                context,
                title: '跟进方案',
                startAt: DateTime(2026, 9, 10),
                dueAt: DateTime(2026, 9, 12),
                kind: '事项',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('确认创建事项'), findsOneWidget);
    expect(find.text('确认创建「跟进方案」？'), findsOneWidget);
    expect(find.text('周期：2026-09-10 ~ 2026-09-12'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-create-confirm-ok')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('editor save requires dates before confirmation', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: TaskEditorPage(session: _session)),
    );
    await tester.pumpAndSettle();
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '客户闭环');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请选择开始时间和结束时间'), findsOneWidget);
    expect(find.text('确认创建主目标'), findsNothing);
    expect(find.text('新建主目标'), findsOneWidget);
  });

  testWidgets('quick create requires start/end before confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openTaskQuickCreate(context, session: _session, asGroup: false),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('开始时间'), findsOneWidget);
    expect(find.textContaining('结束时间'), findsOneWidget);
    expect(find.text('截止'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '跟进方案');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('请选择开始时间和结束时间'), findsOneWidget);
    expect(find.text('确认创建子目标'), findsNothing);
    expect(find.text('新建子目标'), findsOneWidget);
  });
}
