import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/qianji/native_qianji_task_people_page.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = AuthSession(
  phone: '13812345678',
  userId: 1001,
  token: 'test-token',
  apiBase: 'https://test.api',
  roles: ['ADMIN'],
  taskLookupAccess: true,
);

TaskItem _task({
  required int id,
  required int ownerId,
  required String owner,
  required int departmentId,
  required String title,
  String status = 'active',
  bool overdue = false,
  int progress = 0,
  int subtaskCount = 0,
  String acceptance = '有验收',
}) {
  return TaskItem(
    id: id,
    title: title,
    ownerUserId: ownerId,
    creatorUserId: 9,
    ownerName: owner,
    departmentId: departmentId,
    status: status,
    overdue: overdue,
    progressPct: progress,
    subtaskCount: subtaskCount,
    acceptanceCriteria: acceptance,
    dueAt: DateTime(2026, 9, 12),
  );
}

void main() {
  test('超期任务归到需关注，办完的归到按期', () {
    final people = groupTaskPeople(
      [
        _task(
          id: 1,
          ownerId: 1,
          owner: '林嘉宁',
          departmentId: 1,
          title: '跟进合同',
          overdue: true,
        ),
        _task(
          id: 2,
          ownerId: 2,
          owner: '陈丽',
          departmentId: 2,
          title: '月结核对',
          status: 'completed',
          progress: 100,
        ),
      ],
      departmentNames: const {1: '销售部', 2: '财务部'},
    );
    final late = taskPeopleRead(people.firstWhere((person) => person.name == '林嘉宁'));
    final done = taskPeopleRead(people.firstWhere((person) => person.name == '陈丽'));
    expect(late.label, '超期未结');
    expect(late.focus, TaskPeopleFocus.attention);
    expect(done.label, '按期');
    expect(done.focus, TaskPeopleFocus.onTime);
    expect(people.firstWhere((person) => person.name == '林嘉宁').departmentName, '销售部');
    final withAvatar = groupTaskPeople(
      [
        TaskItem(
          id: 9,
          title: '补头像',
          ownerUserId: 7,
          creatorUserId: 1,
          ownerName: '周致远',
          ownerAvatarPreset: 'preset-a',
          ownerAvatarUrl: 'https://cdn.example/a.png',
        ),
      ],
    ).single;
    expect(withAvatar.avatarPreset, 'preset-a');
    expect(withAvatar.avatarUrl, 'https://cdn.example/a.png');
  });

  testWidgets('任务页按员工展示任务状态，需关注只留下超期的人', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final people = groupTaskPeople(
      [
        _task(
          id: 88,
          ownerId: 1,
          owner: '林嘉宁',
          departmentId: 1,
          title: '跟进华东柴油合同',
          overdue: true,
          progress: 40,
          subtaskCount: 2,
          acceptance: '',
        ),
        _task(
          id: 3,
          ownerId: 2,
          owner: '陈丽',
          departmentId: 2,
          title: '完成进项核对',
          status: 'completed',
          progress: 100,
        ),
      ],
      departmentNames: const {1: '销售部', 2: '财务部'},
    );
    final snapshot = TaskPeopleSnapshot(
      departments: const [
        TaskPersonDept(id: 1, name: '销售部'),
        TaskPersonDept(id: 2, name: '财务部'),
      ],
      people: people,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeQianjiTaskPeoplePage(
            session: _session,
            onBack: () {},
            loadSnapshot: (_) async => snapshot,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('林嘉宁'), findsOneWidget);
    expect(find.text('陈丽'), findsOneWidget);
    expect(find.text('超期未结'), findsOneWidget);
    expect(find.text('按期'), findsWidgets);
    expect(find.text('销售部'), findsWidgets);
    expect(find.text('无验收 1'), findsOneWidget);

    await tester.tap(find.text('需关注'));
    await tester.pumpAndSettle();
    expect(find.text('林嘉宁'), findsOneWidget);
    expect(find.text('陈丽'), findsNothing);

    await tester.tap(find.text('林嘉宁'));
    await tester.pumpAndSettle();
    expect(find.text('跟进华东柴油合同'), findsOneWidget);
    expect(find.text('已超期'), findsOneWidget);
  });
}
