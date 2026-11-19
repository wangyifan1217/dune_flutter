import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_chat_card.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_detail.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_service.dart';
import 'package:dunes_app/features/hr_performance/native_hr_performance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AuthSession testSession(int id) => AuthSession(
  phone: '13800138000',
  userId: id,
  token: 'test',
  apiBase: 'https://example.com/api/v1',
  roles: [],
);
Map<String, dynamic> sample({
  int id = 1,
  int userId = 1,
  String name = '员工甲',
  String department = '研发部',
  String stage = 'indicators',
  List<String> actions = const [],
  bool draft = false,
}) => {
  'id': id,
  'userId': userId,
  'version': 1,
  'month': '2026-10',
  'stage': stage,
  'actions': actions,
  'todoGroups': actions.contains('submit_review') ? ['初评'] : [],
  'draftVisible': draft,
  'adjustmentDueAt': '2026-11-04T23:59:59+08:00',
  'snapshot': {
    'name': name,
    'departmentName': department,
    'positionName': '工程师',
    'templateName': '技术量表',
    'blockers': [],
    'historyVerified': true,
    'workflow': {'requests': [], 'bonuses': []},
    'lines': [
      {
        'indicatorId': 'target',
        'name': '目标完成度',
        'weight': 100,
        'suggestedScore': 90,
        'score': draft ? 90 : null,
        'taskIds': [9],
      },
    ],
    'evidence': [
      {'id': 9, 'title': '完成交付任务', 'completedAt': '2026-10-20T08:00:00Z'},
    ],
  },
};

class FakeHR extends HrPerformanceService {
  FakeHR(super.session, this.rows, {this.hr = false, this.manager = false});
  final bool hr, manager;
  List<Map<String, dynamic>> rows;
  Map<String, dynamic>? lastCommand;
  @override
  Future<HrPerformanceAccess> access() async => HrPerformanceAccess(
    allowed: hr || manager,
    team: manager,
    all: hr,
    hr: hr,
  );
  @override
  Future<List<HrPerformanceRecord>> records(String month, String scope) async =>
      rows
          .where((r) => scope != 'mine' || r['userId'] == session.userId)
          .map((r) => HrPerformanceRecord.fromJson({...r, 'month': month}))
          .toList();
  @override
  Future<List<Map<String, dynamic>>> alerts() async => [];
  @override
  Future<List<Map<String, dynamic>>> logs(int id) async => [];
  @override
  Future<Map<String, dynamic>> options(int id) async => {
    'config': {
      'rules': {'decimalPlaces': 1, 'remarkBelow': 60, 'appealMinLength': 10},
      'indicators': [
        {'id': 'target', 'name': '目标完成度', 'weight': 100, 'enabled': true},
      ],
      'templates': [],
      'adjustmentItems': [],
      'exemptionReasons': ['其他'],
    },
    'tasks': [],
    'missingTaskIds': [],
  };
  @override
  Future<HrPerformanceRecord> action(
    HrPerformanceRecord record,
    Map<String, dynamic> command,
  ) async {
    lastCommand = command;
    final index = rows.indexWhere((r) => r['id'] == record.id);
    final stage = command['action'] == 'confirm_indicators'
        ? 'review'
        : command['action'] == 'submit_review'
        ? 'calibration'
        : record.stage;
    rows[index] = {
      ...rows[index],
      'stage': stage,
      'actions': <String>[],
      'version': record.version + 1,
    };
    return HrPerformanceRecord.fromJson(rows[index]);
  }

  @override
  Future<Map<String, dynamic>> summary(
    String month,
    List<int> ids, {
    bool confirmScores = false,
  }) async => {
    'hrPerformanceSummary': true,
    'month': month,
    'hasScores': false,
    'progress': {'indicators': ids.length},
    'rows': [
      for (final r in rows.where((r) => ids.contains(r['id'])))
        {
          'id': r['id'],
          'userId': r['userId'],
          'name': (r['snapshot'] as Map)['name'],
          'stage': r['stage'],
        },
    ],
  };
}

class FakeConversations extends ConversationService {
  FakeConversations() : super(session: testSession(1));
  Map<String, dynamic>? sentPayload;
  int? sentTo;
  @override
  Future<List<NativeConversation>> fetchConversations({
    String query = '',
  }) async => [
    NativeConversation(
      id: 77,
      kind: 'GROUP',
      title: '人事测试会话',
      unreadCount: 0,
      preview: '已有会话',
      updatedAt: DateTime(2026, 11, 1),
    ),
  ];
  @override
  Future<NativeChatMessage?> sendText(
    int conversationId,
    String text, {
    Map<String, dynamic>? payload,
  }) async {
    sentTo = conversationId;
    sentPayload = payload;
    return null;
  }
}

class FakeUrge extends FakeHR {
  FakeUrge(super.session, super.rows) : super(hr: true);
  List<int> sentIds = [];
  @override
  Future<List<Map<String, dynamic>>> batch(
    List<HrPerformanceRecord> records,
    String action,
    String reason,
  ) async {
    sentIds = records.map((r) => r.id).toList();
    lastCommand = {'action': action, 'reason': reason};
    return [
      for (final r in records) {'id': r.id, 'success': true},
    ];
  }
}

Future<void> mount(
  WidgetTester tester,
  double width,
  FakeHR service, {
  FakeConversations? conversations,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NativeHrPerformancePage(
          session: service.session,
          service: service,
          conversationService: conversations,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openRow(WidgetTester tester, double width, String name) async {
  if (width < 640) {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('desktop roster and filters collapse without losing selection', (
    tester,
  ) async {
    final service = FakeHR(testSession(4), [
      sample(id: 1, userId: 1, name: '员工甲', department: '研发部'),
      sample(id: 2, userId: 6, name: '员工乙', department: '研发部'),
    ], hr: true);
    await mount(tester, 900, service);
    await tester.tap(find.text('全员'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-dept-select-name-研发部')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 人'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hr-roster-collapse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hr-roster-expand')), findsOneWidget);
    expect(find.byKey(const ValueKey('hr-dept-select-name-研发部')), findsNothing);
    expect(find.text('已选 2 人'), findsOneWidget);
    expect(find.byType(HrPerformanceDetail), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hr-roster-expand')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('hr-dept-select-name-研发部')),
          )
          .value,
      isTrue,
    );
    await tester.enterText(find.byType(TextField).first, '员工乙');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hr-filter-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('已启用筛选 · 当前 1 人'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hr-filter-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('员工乙'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('HR can revoke exemption with a reason', (tester) async {
    final record = sample(stage: 'exempt', actions: ['undo_exempt']);
    final service = FakeHR(testSession(4), [record], hr: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HrPerformanceDetail(
            session: service.session,
            service: service,
            record: HrPerformanceRecord.fromJson(record),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销免考核'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原有截止时间保持不变'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hr-reason')), '误操作，恢复考核');
    await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
    await tester.pumpAndSettle();
    expect(service.lastCommand?['action'], 'undo_exempt');
    expect(service.lastCommand?['reason'], '误操作，恢复考核');
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('urge previews eligible people and excludes others', (
    tester,
  ) async {
    final service = FakeUrge(testSession(4), [
      sample(id: 1, name: '员工甲', stage: 'review', actions: ['urge']),
      sample(id: 2, userId: 2, name: '员工乙', stage: 'exempt'),
    ]);
    await mount(tester, 360, service);
    await tester.tap(find.text('全员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('督办'));
    await tester.pumpAndSettle();
    expect(find.text('发送 1 人 · 跳过 1 人'), findsOneWidget);
    expect(find.textContaining('已跳过无权督办或不在办理中的人员：员工乙'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hr-reason')), '请及时完成评分');
    await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
    await tester.pumpAndSettle();
    expect(service.sentIds, [1]);
    expect(service.lastCommand?['reason'], '请及时完成评分');
    await tester.pump(const Duration(seconds: 4));
  });
  for (final width in [360.0, 900.0]) {
    testWidgets('executive skip shows HR return to initial review at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = sample(stage: 'hr', actions: ['return_hr'], draft: true);
      (data['snapshot'] as Map<String, dynamic>)['divisionSupervisorName'] =
          '许正阳';
      final service = FakeHR(testSession(4), [data], hr: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceDetail(
              session: service.session,
              record: HrPerformanceRecord.fromJson(data),
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('退回初评'), findsOneWidget);
      expect(find.text('退回校准'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('hr-action-return_hr')));
      await tester.pumpAndSettle();
      expect(find.text('该考核跳过分管校准，将退回直属主管初评。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hr-reason')),
        '请重新核对评分',
      );
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'return_hr');
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
    testWidgets('employee confirms indicators at $width', (tester) async {
      final service = FakeHR(testSession(1), [
        sample(actions: ['confirm_indicators', 'request_adjustment']),
      ]);
      await mount(tester, width, service);
      expect(
        find.byKey(const ValueKey('hr-action-confirm_indicators')),
        findsOneWidget,
      );
      expect(find.text('搜索姓名、部门或岗位'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('hr-action-confirm_indicators')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'confirm_indicators');
      expect(find.text('主管初评'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'my tab directly shows own record and switches back from team at $width',
      (tester) async {
        final service = FakeHR(testSession(1), [
          sample(name: '员工甲'),
          sample(id: 2, userId: 2, name: '员工乙'),
        ], hr: true);
        await mount(tester, width, service);
        expect(find.byKey(const ValueKey('hr-mine-1')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('hr-dept-select-name-研发部')),
          findsNothing,
        );
        await tester.tap(find.text('全员'));
        await tester.pumpAndSettle();
        expect(find.text('员工乙'), findsWidgets);
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('hr-mine-1')), findsOneWidget);
        expect(find.text('员工乙'), findsNothing);
      },
    );
    testWidgets(
      'record link opens another person rather than my record at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeHR(testSession(1), [
          sample(),
          sample(id: 2, userId: 2, name: '员工乙'),
        ], hr: true);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeHrPerformancePage(
                session: service.session,
                service: service,
                initialRecordId: 2,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('员工乙'), findsWidgets);
        expect(find.byKey(const ValueKey('hr-mine-1')), findsNothing);
        if (width >= 640) {
          expect(find.byType(HrPerformanceDetail), findsOneWidget);
        }
      },
    );
    testWidgets('manager scores with a reason at $width', (tester) async {
      final service = FakeHR(testSession(2), [
        sample(
          stage: 'review',
          actions: ['submit_review', 'urge'],
          draft: true,
        ),
      ], manager: true);
      await mount(tester, width, service);
      await tester.tap(find.text('待办'));
      await tester.pumpAndSettle();
      await openRow(tester, width, '员工甲');
      await tester.tap(find.byKey(const ValueKey('hr-action-submit_review')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hr-score-target')),
        '89.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('hr-remark-target')),
        '根据交付延期记录扣减',
      );
      await tester.tap(find.byKey(const ValueKey('hr-sheet-submit')));
      await tester.pumpAndSettle();
      expect(service.lastCommand?['action'], 'submit_review');
      expect((service.lastCommand?['lines'] as List).first['score'], 89.5);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('forward selects an existing conversation at $width', (
      tester,
    ) async {
      final service = FakeHR(testSession(1), [sample()]);
      final conversations = FakeConversations();
      await mount(tester, width, service, conversations: conversations);
      await tester.tap(find.text('转发'));
      await tester.pumpAndSettle();
      expect(find.text('人事测试会话'), findsOneWidget);
      await tester.tap(find.text('人事测试会话'));
      await tester.pumpAndSettle();
      expect(conversations.sentTo, 77);
      expect(conversations.sentPayload?['hrPerformanceSummary'], isTrue);
      expect(
        conversations.sentPayload?.containsKey('kpiScoreSummary'),
        isFalse,
      );
      expect(
        (conversations.sentPayload?['rows'] as List).first.containsKey('total'),
        isFalse,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('department checkbox selects everyone below at $width', (
      tester,
    ) async {
      final service = FakeHR(testSession(4), [
        sample(id: 1, userId: 1, name: '员工甲', department: '研发部'),
        sample(id: 2, userId: 6, name: '员工乙', department: '研发部'),
        sample(id: 3, userId: 7, name: '员工丙', department: '财务部'),
      ], hr: true);
      await mount(tester, width, service);
      await tester.tap(find.text('全员'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hr-dept-select-name-研发部')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 人'), findsOneWidget);
      expect(find.text('员工丙'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hr-dept-select-name-研发部')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 人'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('HR filters the roster at $width', (tester) async {
      final service = FakeHR(testSession(4), [
        sample(name: '员工甲', department: '研发部'),
        sample(id: 2, userId: 6, name: '员工乙', department: '财务部'),
      ], hr: true);
      await mount(tester, width, service);
      await tester.tap(find.text('全员'));
      await tester.pumpAndSettle();
      if (width < 640) {
        await tester.tap(find.byTooltip('筛选'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('全部部门'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('财务部'),
          matching: find.byType(MenuItemButton),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 640) {
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }
      expect(find.text('员工甲'), findsNothing);
      expect(find.text('员工乙'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('stage chips filter the roster at $width', (tester) async {
      final service = FakeHR(testSession(4), [
        sample(name: '员工甲', stage: 'review'),
        sample(id: 2, userId: 6, name: '员工乙', stage: 'hr', department: '财务部'),
        sample(
          id: 3,
          userId: 7,
          name: '员工丙',
          stage: 'exempt',
          department: '财务部',
        ),
      ], hr: true);
      await mount(tester, width, service);
      await tester.tap(find.text('全员'));
      await tester.pumpAndSettle();
      expect(find.text('全部节点'), findsNothing);
      expect(find.byKey(const ValueKey('hr-stage-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('hr-stage-exempt')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('hr-stage-hr')));
      await tester.tap(find.byKey(const ValueKey('hr-stage-hr')));
      await tester.pumpAndSettle();
      expect(find.text('员工甲'), findsNothing);
      expect(find.text('员工乙'), findsWidgets);
      expect(find.text('员工丙'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('hr-stage-hr')));
      await tester.tap(find.byKey(const ValueKey('hr-stage-hr')));
      await tester.pumpAndSettle();
      expect(find.text('员工甲'), findsWidgets);
      expect(find.text('员工丙'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('hr-stage-all')));
      await tester.tap(find.byKey(const ValueKey('hr-stage-all')));
      await tester.pumpAndSettle();
      expect(find.text('员工乙'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'chat progress cards hide score fields even when payload contains them',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HrPerformanceChatCard(
              session: testSession(1),
              payload: {
                'hrPerformanceSummary': true,
                'month': '2026-10',
                'hasScores': false,
                'rows': [
                  {
                    'id': 1,
                    'name': '员工甲',
                    'stage': 'final',
                    'total': 99,
                    'grade': '草稿等级',
                    'coefficient': 9,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('草稿等级'), findsNothing);
      expect(find.textContaining('99'), findsNothing);
    },
  );
}
