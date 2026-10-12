import 'dart:async';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/tasks/task_widgets.dart';
import 'package:dunes_app/features/tasks/task_subtasks_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TaskItem task(
  int id, {
  String title = '任务',
  String status = 'active',
  int progress = 50,
  bool overdue = false,
}) => TaskItem(
  id: id,
  title: title,
  ownerUserId: 1,
  creatorUserId: 2,
  ownerName: '王琳',
  creatorName: '张明',
  status: status,
  progressPct: progress,
  overdue: overdue,
  subtaskCount: 2,
  completedSubtaskCount: 1,
  startAt: DateTime(2026, 10, 1),
  dueAt: DateTime(2026, 10, 15),
);
Future<void> host(
  WidgetTester tester,
  Future<TaskDetail> Function() load,
  ValueChanged<int> open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DunesTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => TaskSubtasksDialog(
                task: task(1),
                loadDetail: load,
                onOpenTask: open,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'compact goal keeps independent subtask, detail and share actions',
    (tester) async {
      var details = 0;
      var subtasks = 0;
      var shares = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: DunesTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 340,
                height: 220,
                child: TaskWorkbenchCard(
                  task: task(1, title: '长标题任务用于检查紧凑卡片布局和负责人信息'),
                  groupMode: true,
                  onTap: () => details++,
                  onSubtasks: () => subtasks++,
                  onShare: () => shares++,
                  groupTrailingAction: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '还有 1 个子目标未完成',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('子任务'));
      expect(subtasks, 1);
      expect(details, 0);
      await tester.tap(find.text('查看详情'));
      expect(details, 1);
      await tester.tap(find.byTooltip('转发到 IM'));
      expect(shares, 1);
    },
  );
  testWidgets('dialog loads on demand and opens the selected child', (
    tester,
  ) async {
    final pending = Completer<TaskDetail>();
    int? opened;
    await host(tester, () => pending.future, (id) => opened = id);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(
      TaskDetail(
        task: task(1),
        subtasks: [
          task(2, title: '已完成的子任务', status: 'completed', progress: 100),
          task(3, title: '核对到账', overdue: true),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('共 2 项 · 已完成 1 项 · 逾期 1 项'), findsOneWidget);
    expect(find.text('负责人：王琳'), findsNWidgets(2));
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('核对到账'));
    await tester.pumpAndSettle();
    expect(opened, 3);
    expect(find.text('子任务概览'), findsNothing);
  });
  testWidgets('dialog retries failed loads and handles no visible children', (
    tester,
  ) async {
    var count = 0;
    await host(tester, () async {
      if (count++ == 0) throw Exception('网络连接失败');
      return TaskDetail(task: task(1));
    }, (_) {});
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(count, 2);
    expect(find.text('暂无可查看的子任务'), findsOneWidget);
  });
  testWidgets('narrow dialog scrolls many children with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: DunesTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: TaskSubtasksDialog(
            task: task(1),
            loadDetail: () async => TaskDetail(
              task: task(1),
              subtasks: [
                for (var i = 0; i < 20; i++)
                  task(i + 2, title: '子任务 $i 较长的任务名称需要正确换行展示'),
              ],
            ),
            onOpenTask: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('子任务 19 较长的任务名称需要正确换行展示'),
      250,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('子任务 19 较长的任务名称需要正确换行展示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
