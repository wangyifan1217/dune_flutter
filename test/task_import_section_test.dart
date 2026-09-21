import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/tasks/native_task_import_section.dart';
import 'package:dunes_app/features/tasks/task_management_api.dart';
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
  testWidgets('kind tabs switch between task and probation templates', (
    tester,
  ) async {
    var kind = 'task';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TaskImportKindTabs(
              kind: kind,
              onChanged: (value) => setState(() => kind = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('任务模板'), findsOneWidget);
    expect(find.text('试用期任务模板'), findsOneWidget);
    await tester.tap(find.text('试用期任务模板'));
    await tester.pump();
    expect(kind, 'probation');
  });

  testWidgets('employee card shows selected person and probation period', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TaskImportEmployeeCard(
            session: _session,
            employee: TaskImportEmployee(
              id: 42,
              displayName: '李晨阳',
              departmentName: '客服',
              probationStartAt: '2026-06-01',
              probationEndAt: '2026-09-01',
            ),
            onPick: _noop,
          ),
        ),
      ),
    );

    expect(find.text('李晨阳'), findsOneWidget);
    expect(find.textContaining('试用期 2026-06-01 至 2026-09-01'), findsOneWidget);
    expect(find.text('更换'), findsOneWidget);
  });

  testWidgets('drop zone and preview stats show file and error counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TaskImportDropZone(
                fileName: '试用期目标模板.xlsx',
                dragging: false,
                onPick: _noop,
              ),
              const TaskImportPreviewStats(
                preview: TaskImportPreview(
                  importId: '1',
                  total: 21,
                  valid: 21,
                  invalid: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('试用期目标模板.xlsx'), findsOneWidget);
    expect(find.text('总行数'), findsOneWidget);
    expect(find.text('可导入'), findsOneWidget);
    expect(find.text('错误'), findsOneWidget);
    expect(find.text('21'), findsNWidgets(2));
  });
}

void _noop() {}
