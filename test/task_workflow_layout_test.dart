import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/tasks/native_task_form.dart';
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
