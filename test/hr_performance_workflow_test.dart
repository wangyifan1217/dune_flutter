import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:dunes_app/features/hr_performance/hr_performance_chat_card.dart';
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
  FakeHR(AuthSession actor, this.rows, {this.hr = false, this.manager = false})
    : super(actor);
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
  for (final width in [360.0, 900.0]) {
    testWidgets('employee confirms indicators at $width', (tester) async {
      final service = FakeHR(testSession(1), [
        sample(actions: ['confirm_indicators', 'request_adjustment']),
      ]);
      await mount(tester, width, service);
      await openRow(tester, width, '员工甲');
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
      await tester.tap(find.text('财务部').last);
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
