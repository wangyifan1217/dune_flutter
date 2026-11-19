import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/tasks/native_task_form.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AuthSession(
  phone: '13800000000',
  userId: 1,
  token: 't',
  apiBase: 'http://127.0.0.1',
  roles: [],
  displayName: '测试用户',
);

void main() {
  testWidgets('subtask assignee picker searches the assignable team', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'task.guide.v3.create_sub.1': true,
    });
    final queries = <String?>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      final params = request.url.queryParameters;
      Object data = <String, dynamic>{};
      if (path.endsWith('/rd-intake')) {
        data = {'canAssignTeam': true};
      } else if (path.endsWith('/assignees')) {
        expect(params['scope'], 'subtask');
        queries.add(params['q']);
        data = [
          if (params['q'] == null) {'id': 2, 'displayName': '可指派成员'},
        ];
      } else {
        expect(path, endsWith('/rules'));
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode({'success': true, 'data': data})),
        200,
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: TaskEditorDialog(
            session: _session,
            parentTaskId: 1,
            parentTask: TaskItem(
              id: 1,
              title: '主任务',
              ownerUserId: 1,
              creatorUserId: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('给团队成员'));
      await tester.pumpAndSettle();
      final picker = find.text('请选择团队成员');
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      expect(find.text('可指派成员'), findsOneWidget);

      final search = find.widgetWithText(TextField, '输入姓名筛选');
      await tester.enterText(search, '其他同事');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(queries, [null, '其他同事']);
      expect(find.text('没有符合指派范围的团队成员'), findsOneWidget);
      expect(find.text('可指派成员'), findsNothing);
    }, () => client);
  });
}
