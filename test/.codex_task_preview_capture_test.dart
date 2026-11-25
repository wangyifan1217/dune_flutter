import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/meeting/meeting_task_suggestions_section.dart';
import 'package:dunes_app/features/tasks/native_task_daily_report_page.dart';
import 'package:dunes_app/features/tasks/native_task_form.dart';
import 'package:dunes_app/features/tasks/native_task_goal_report_page.dart';
import 'package:dunes_app/features/tasks/native_task_home_pane.dart';
import 'package:dunes_app/features/tasks/native_task_probation_pane.dart';
import 'package:dunes_app/features/tasks/task_api.dart';
import 'package:dunes_app/features/tasks/task_management_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const session = AuthSession(phone: '', userId: 91, token: 'fixture',
  apiBase: 'https://example.test', roles: [], displayName: '林晓', jobTitle: '财务专员');

const fixtures = [
  {'id': 21, 'title': '核对十一月供应商结算清单', 'category': '职能',
    'subCategory': '财务', 'ownerUserId': 92, 'ownerName': '周宁', 'creatorUserId': 91,
    'status': 'in_progress', 'progressPct': 65, 'overdue': true,
    'subtaskCount': 3, 'completedSubtaskCount': 2,
    'startAt': '2026-11-18T09:00:00+08:00', 'dueAt': '2026-11-23T18:00:00+08:00'},
  {'id': 22, 'title': '整理门店培训材料并确认排期', 'category': '业务',
    'subCategory': '运营', 'ownerUserId': 93, 'ownerName': '许然', 'creatorUserId': 91,
    'status': 'pending_assignment', 'progressPct': 0,
    'startAt': '2026-11-25T09:00:00+08:00', 'dueAt': '2026-11-27T18:00:00+08:00'},
  {'id': 23, 'title': '完成供应商对账表复核', 'category': '职能',
    'subCategory': '财务', 'ownerUserId': 94, 'ownerName': '沈言', 'creatorUserId': 91,
    'status': 'completed', 'progressPct': 100, 'completedAt': '2026-11-21T17:30:00+08:00'},
  {'id': 24, 'title': '更新十二月费用归集模板', 'category': '职能',
    'subCategory': '财务', 'ownerUserId': 93, 'ownerName': '许然', 'creatorUserId': 91,
    'status': 'in_progress', 'progressPct': 35, 'dueAt': '2026-11-30T18:00:00+08:00'},
];

final reportRows = [
  {'goalId': 21, 'title': '核对十一月供应商结算清单', 'ownerId': 92,
    'status': 'in_progress', 'progress': 65, 'reporterId': 92,
    'reportDate': '2026-11-24', 'submittedAt': '2026-11-24T17:42:00+08:00',
    'taskId': 26, 'taskTitle': '复核华东区凭证',
    'workDone': '已核对 18 家供应商，待确认 2 笔差额。',
    'blockers': '等待业务补充签收凭证。'},
  {'goalId': 24, 'title': '更新十二月费用归集模板', 'ownerId': 93,
    'status': 'in_progress', 'progress': 35, 'reporterId': 93,
    'reportDate': '2026-11-24', 'submittedAt': '2026-11-24T16:20:00+08:00',
    'taskId': 24, 'workDone': '已整理各部门使用的成本分类。'},
];

http.Client mock() => MockClient((request) async {
  final uri = request.url;
  final path = uri.path;
  Object data = <String, dynamic>{};
  if (path.endsWith('/goal-progress')) {
    final rows = uri.queryParameters['goalId'] == '21'
        ? [reportRows.first, {...reportRows.first, 'taskId': 21,
            'reportDate': '2026-11-23', 'workDone': '已收齐区域结算清单并整理差异。'}]
        : reportRows;
    data = {'items': rows, 'names': {'92': '周宁', '93': '许然'}};
  } else if (path.endsWith('/probation-goals')) {
    data = {'total': 3, 'departments': ['财务部', '运营中心'], 'items': [
      {'userId': 92, 'name': '周宁', 'employeeNo': 'DE0123', 'department': '财务部',
        'probationEndAt': '2026-12-18', 'summary': {'total': 4, 'completed': 2,
          'progress': 65, 'updatedAt': '2026-11-24 17:42'}},
      {'userId': 93, 'name': '许然', 'employeeNo': 'DE0124', 'department': '运营中心',
        'probationEndAt': '2027-01-08', 'summary': {'total': 3, 'completed': 1,
          'progress': 40, 'updatedAt': '2026-11-23 16:10'}},
      {'userId': 94, 'name': '沈言', 'employeeNo': 'DE0125', 'department': '运营中心',
        'probationEndAt': '2027-01-15', 'summary': {'total': 0, 'completed': 0, 'progress': 0}},
    ]};
  } else if (path.endsWith('/task-daily-reports')) {
    data = {'canSubmit': true, 'isWorkday': true,
      'businessDate': '2026-11-25', 'candidates': [
        {...fixtures.first, 'ownerUserId': 91, 'ownerName': '林晓'},
      ]};
  } else if (path.endsWith('/history')) {
    data = {'items': []};
  } else if (path.endsWith('/tasks')) {
    final rows = uri.queryParameters['goalRole'] == 'assigned'
        ? fixtures : fixtures.where((row) => row['status'] == 'in_progress').toList();
    data = {'items': rows, 'total': rows.length};
  } else if (path.endsWith('/rd-intake')) {
    data = {'canCreate': true, 'canAssignTeam': true, 'owners': []};
  }
  return http.Response.bytes(utf8.encode(jsonEncode({'success': true, 'data': data})), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

final key = GlobalKey();
const out = '/Users/wang/Documents/ChatGPT/沙丘/任务页面预览';

Future<void> capture(WidgetTester tester, String file) async {
  print('capture starts $file');
  await tester.pumpAndSettle();
  print('settled $file');
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    print('toImage');
    final image = boundary.toImageSync(pixelRatio: 1.5);
    print('toByteData');
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$out/$file.png').writeAsBytes(data.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull);
}

Future<void> mount(WidgetTester tester, Widget page, Size size) async {
  print('mount $size');
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    RepaintBoundary(key: key, child: MaterialApp(
      theme: size.width > 750 ? DunesTheme.desktop() : DunesTheme.light(),
      home: page,
    )),
  );
  await tester.pumpAndSettle();
  print('mount settled');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final pair in [
      ('Geist', 'Geist-Regular.ttf'),
      ('Noto Sans SC', 'NotoSansSC-Regular.ttf'),
      ('MaterialIcons', '/Users/wang/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    ]) {
      final path = pair.$2.startsWith('/') ? pair.$2 : 'assets/fonts/${pair.$2}';
      final bytes = File(path).readAsBytesSync();
      final loader = FontLoader(pair.$1)..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  testWidgets('render current task screens', (tester) async {
    SharedPreferences.setMockInitialValues({
      'task.guide.v3.home.91': true,
      'task.guide.v3.create_main.91': true,
      'task.guide.v3.daily_report.91': true,
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await mount(tester, const _TaskScreen(), const Size(1040, 760));
      await tester.tap(find.text('我分派'));
      await capture(tester, '01-我分派');
      await mount(tester, Scaffold(
        appBar: AppBar(title: const Text('试用期目标')),
        body: NativeTaskProbationPane(api: TaskManagementApi(session), onImport: () {}),
      ), const Size(1040, 620));
      await capture(tester, '02-试用期目标');
      await mount(tester, NativeTaskGoalReportPage(api: TaskApi(session)), const Size(1040, 620));
      await tester.tap(find.text('核对十一月供应商结算清单'));
      await capture(tester, '03-目标进展');
      await mount(tester, NativeTaskDailyReportPage(
        session: session, onBack: () {}, initialDate: DateTime(2026, 11, 25),
      ), const Size(410, 820));
      await capture(tester, '04-手机日报');
      await mount(tester, Scaffold(
        appBar: AppBar(title: const Text('会议详情')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('十一月结算进度沟通会'),
            const MeetingTaskSuggestionsSection(session: session, meetingId: 7, canLinkTasks: true),
          ]),
        ),
      ), const Size(650, 570));
      await tester.tap(find.text('关联任务'));
      await capture(tester, '05-会议关联任务');
      await mount(tester, const TaskEditorPage(session: session), const Size(460, 920));
      await tester.ensureVisible(find.text('每月重复'));
      await capture(tester, '06-每月重复');
    }, mock);
  });
}

class _TaskScreen extends StatefulWidget {
  const _TaskScreen();
  @override
  State<_TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<_TaskScreen> {
  Widget? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('任务'), actions: [?actions]),
    body: NativeTaskHomePane(session: session, embedded: true,
      onChromeChanged: (chrome) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => actions = chrome.trailing);
        });
      }, onOpenSummary: () {}),
  );
}
