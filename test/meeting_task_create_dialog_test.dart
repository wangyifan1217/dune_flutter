import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/meeting/meeting_task_create_dialog.dart';
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
  test('meeting task create requires both dates and due after start', () {
    expect(meetingTaskRangeError(null, null), '请选择开始时间和结束时间');
    expect(
      meetingTaskRangeError(DateTime(2026, 9, 10), null),
      '请选择开始时间和结束时间',
    );
    expect(
      meetingTaskRangeError(DateTime(2026, 9, 12), DateTime(2026, 9, 10)),
      '结束时间不能早于开始时间',
    );
    expect(
      meetingTaskRangeError(DateTime(2026, 9, 10), DateTime(2026, 9, 12)),
      isNull,
    );
  });

  testWidgets('create dialog asks for owner, acceptance and dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMeetingTaskCreateDialog(
              context,
              session: _session,
              title: '跟进方案',
              description: '会后输出一版方案',
              acceptanceCriteria: '客户书面确认',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('负责人'), findsOneWidget);
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('客户书面确认'), findsOneWidget);
    await tester.tap(find.text('确认创建'));
    await tester.pump();
    expect(find.text('请选择开始时间和结束时间'), findsOneWidget);
    expect(find.text('创建任务'), findsOneWidget);
  });
}
