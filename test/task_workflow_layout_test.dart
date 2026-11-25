import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/meeting/meeting_task_suggestions_section.dart';
import 'package:dunes_app/features/tasks/native_task_form.dart';
import 'package:dunes_app/features/tasks/native_task_goal_report_page.dart';
import 'package:dunes_app/features/tasks/task_api.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/tasks/task_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AuthSession(
  phone: '',
  userId: 91,
  token: 'test',
  apiBase: 'https://example.test',
  roles: [],
  displayName: '测试用户',
  jobTitle: '财务专员',
);

void main() {
  test('验收方式保留补充说明，岗位匹配默认分类', () {
    expect(taskCategoryForPosition('行政主管'), ('职能', '行政'));
    expect(taskCategoryForPosition('用户运营'), ('业务', '运营'));
    expect(
      taskAcceptanceText('提交交付物\n报价明细', '提交交付物', '经负责人确认'),
      '经负责人确认\n报价明细',
    );
  });

  testWidgets('会议主持人可搜索并关联现有任务', (tester) async {
    var linked = false;
    final queries = <String>[];
    await http.runWithClient(
      () async {
        await tester.binding.setSurfaceSize(const Size(360, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MeetingTaskSuggestionsSection(
                  session: _session,
                  meetingId: 7,
                  canLinkTasks: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('关联任务'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '客户');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(queries.last, '客户');
        await tester.tap(find.text('客户拜访'));
        await tester.pumpAndSettle();
        expect(linked, isTrue);
        expect(find.text('已关联任务'), findsOneWidget);
        expect(find.text('客户拜访'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      },
      () => MockClient((request) async {
        final path = request.url.path;
        Object data;
        if (path.endsWith('/meetings/7/task-suggestions')) {
          data = {
            'syncedTasks': [
              if (linked) {'taskId': 21, 'taskTitle': '客户拜访'},
            ],
          };
        } else if (path.endsWith('/tasks/21/links')) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'kind': 'meeting', 'meetingId': 7});
          linked = true;
          data = {'id': 1};
        } else {
          expect(request.url.queryParameters['scope'], 'editable_main');
          queries.add(request.url.queryParameters['q'] ?? '');
          data = {
            'items': [
              {'id': 21, 'title': '客户拜访'},
            ],
          };
        }
        return http.Response.bytes(
          utf8.encode(jsonEncode({'success': true, 'data': data})),
          200,
        );
      }),
    );
  });

  testWidgets('目标进展以北京时间显示提交时间并可展开日报', (tester) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(home: NativeTaskGoalReportPage(api: TaskApi(_session))),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('2026-11-24 17:42'), findsOneWidget);
        await tester.tap(find.text('核对供应商清单'));
        await tester.pumpAndSettle();
        expect(find.textContaining('子任务 复核凭证'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        final isHistory = request.url.queryParameters['goalId'] == '21';
        final body = {
          'success': true,
          'data': {
            'names': {'91': '测试用户'},
            'items': [
              {
                'goalId': 21,
                'title': '核对供应商清单',
                'ownerId': 91,
                'reporterId': 91,
                'reportDate': '2026-11-24',
                'submittedAt': '2026-11-24T09:42:00Z',
                'taskId': isHistory ? 26 : 21,
                'taskTitle': '复核凭证',
                'workDone': '已复核',
              },
            ],
          },
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
  });

  for (final desktop in [false, true]) {
    testWidgets('${desktop ? 'PC' : '手机'}创建任务沿用紫色表单且无布局溢出', (tester) async {
      SharedPreferences.setMockInitialValues({
        'task.guide.v3.create_main.91': true,
      });
      await tester.binding.setSurfaceSize(
        desktop ? const Size(1200, 800) : const Size(360, 700),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  if (!desktop) return const TaskEditorPage(session: _session);
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            const TaskEditorDialog(session: _session),
                      ),
                      child: const Text('打开表单'),
                    ),
                  );
                },
              ),
            ),
          );
          if (desktop) await tester.tap(find.text('打开表单'));
          await tester.pumpAndSettle();
          expect(find.text('优先级'), findsNothing);
          expect(find.text('职能'), findsWidgets);
          expect(find.text('财务'), findsWidgets);
          expect(find.text(formatTaskYmd(DateTime.now())), findsOneWidget);
          await tester.ensureVisible(find.text('每月重复'));
          await tester.pumpAndSettle();
          expect(find.text('每月重复'), findsOneWidget);
          await tester.tap(find.text('每月重复'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, '每月重复'),
                )
                .value,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {'canAssignTeam': true, 'owners': []},
            }),
            200,
          ),
        ),
      );
    });
  }
}
